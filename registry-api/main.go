package main

import (
	"context"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/MicahParks/keyfunc/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type Config struct {
	S3Endpoint  string
	S3AccessKey string
	S3SecretKey string
	S3UseSSL    bool
	S3Bucket    string

	// S3PublicEndpoint is the endpoint used to generate PRESIGNED download
	// URLs — it must be reachable by the Terraform consumer, not just by the
	// API. The S3 signature binds the host, so the URL cannot be rewritten after
	// signing. Empty → fall back to S3Endpoint (works when API and consumer
	// share a network, e.g. all-in-cluster).
	S3PublicEndpoint string
	S3PublicUseSSL   bool
	// S3Region is set explicitly so the presign client does NOT do a
	// bucket-location lookup (GET /<bucket>/?location=). That call would hit the
	// public endpoint, which is unreachable from inside the container (it points
	// at the host). versitygw's default region is us-east-1.
	S3Region       string
	KeycloakIssuer string
	KeycloakJWKS   string
	ListenAddr     string
	Domain         string

	// AuthMode selects token validation: "keycloak" (OIDC/JWKS, the default and
	// the only mode that supports `terraform login`) or "static" (a fixed set of
	// bearer tokens — used by the Docker Compose setup to drop the Keycloak dep).
	AuthMode string
	// StaticTokens maps a bearer token to the framework storage paths it may
	// access, e.g. {"s3cr3t": {"cis_v600", "soc2"}}.
	StaticTokens map[string][]string

	// DynamicBuild, when true, makes the registry patch-and-cache any module on
	// demand: a cache miss triggers a fetch from UpstreamRegistry + framework
	// patching instead of returning 404. Versions are proxied from upstream.
	DynamicBuild     bool
	UpstreamRegistry string // e.g. "registry.terraform.io"
	BuildScript      string // path to build-dynamic.sh inside the image
	PatchesDir       string // assets anchor; its parent holds transformations/ + frameworks/

	// DirectMode enables the go-getter "direct" endpoint (/m/...): an ad-hoc,
	// framework-less transformation set selected via ?transformation=a,b. Open
	// by design — no token, no entitlement (ADR-009). The upstream allow-list
	// (ALLOWED_MODULES) still applies in the build script.
	DirectMode bool
}

type Server struct {
	config        Config
	s3Client      *minio.Client
	presignClient *minio.Client // generates host-reachable presigned URLs
	jwks          *keyfunc.JWKS
	builds        sync.Map // objectKey -> *sync.Mutex, dedupes concurrent builds
}

// ServiceDiscovery is the response for /.well-known/terraform.json
type ServiceDiscovery struct {
	Login   *LoginConfig `json:"login.v1,omitempty"`
	Modules string       `json:"modules.v1"`
}

type LoginConfig struct {
	Authz      string   `json:"authz"`
	Client     string   `json:"client"`
	GrantTypes []string `json:"grant_types"`
	Ports      []int    `json:"ports"`
	Token      string   `json:"token"`
}

// ModuleVersions is the response for listing versions
type ModuleVersions struct {
	Modules []ModuleVersionList `json:"modules"`
}

type ModuleVersionList struct {
	Versions []ModuleVersion `json:"versions"`
}

type ModuleVersion struct {
	Version string `json:"version"`
}

func main() {
	cfg := Config{
		S3Endpoint:  envOrDefault("S3_ENDPOINT", "versitygw:7070"),
		S3AccessKey: envOrDefault("S3_ACCESS_KEY", "conformer"),
		S3SecretKey: envOrDefault("S3_SECRET_KEY", "conformer-secret"),
		S3UseSSL:    envOrDefault("S3_USE_SSL", "false") == "true",
		S3Bucket:    envOrDefault("S3_BUCKET", "modules"),

		S3PublicEndpoint: os.Getenv("S3_PUBLIC_ENDPOINT"),
		S3PublicUseSSL:   envOrDefault("S3_PUBLIC_USE_SSL", "false") == "true",
		S3Region:         envOrDefault("S3_REGION", "us-east-1"),
		KeycloakIssuer:   envOrDefault("KEYCLOAK_ISSUER", "https://auth.conformer.local/realms/compliance"),
		KeycloakJWKS:     envOrDefault("KEYCLOAK_JWKS_URL", "https://auth.conformer.local/realms/compliance/protocol/openid-connect/certs"),
		ListenAddr:       envOrDefault("LISTEN_ADDR", ":8080"),
		Domain:           envOrDefault("DOMAIN", "conformer.local"),
		AuthMode:         envOrDefault("AUTH_MODE", "keycloak"),
		StaticTokens:     parseStaticTokens(os.Getenv("STATIC_TOKENS")),

		DynamicBuild:     envOrDefault("DYNAMIC_BUILD", "false") == "true",
		UpstreamRegistry: envOrDefault("UPSTREAM_REGISTRY", "registry.terraform.io"),
		BuildScript:      envOrDefault("BUILD_SCRIPT", "/app/scripts/build-dynamic.sh"),
		PatchesDir:       envOrDefault("PATCHES_DIR", "/app/patches"),
		DirectMode:       envOrDefault("DIRECT_MODE", "true") == "true",
	}

	if cfg.DynamicBuild {
		log.Printf("Dynamic build ENABLED — cache misses fetch from %s and patch on demand", cfg.UpstreamRegistry)
	}

	// Initialize S3 client (versitygw)
	s3Client, err := minio.New(cfg.S3Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""),
		Secure: cfg.S3UseSSL,
	})
	if err != nil {
		log.Fatalf("Failed to create S3 client: %v", err)
	}

	// `registry-api upload <zipPath> <objectKey>` — lets the build scripts push
	// artifacts via the Apache-2.0 minio-go SDK instead of bundling the AGPL mc.
	if len(os.Args) >= 2 && os.Args[1] == "upload" {
		if len(os.Args) != 4 {
			log.Fatalf("usage: registry-api upload <zipPath> <objectKey>")
		}
		if uerr := uploadObject(context.Background(), s3Client, cfg.S3Bucket, os.Args[3], os.Args[2]); uerr != nil {
			log.Fatalf("upload failed: %v", uerr)
		}
		log.Printf("uploaded %s", os.Args[3])
		return
	}

	// Ensure the bucket exists. Retry so the API tolerates the S3 store
	// (versitygw) still coming up — avoids depending on a container healthcheck.
	for attempt := 1; ; attempt++ {
		if berr := ensureBucket(context.Background(), s3Client, cfg.S3Bucket); berr == nil {
			break
		} else if attempt >= 30 {
			log.Printf("Warning: ensure bucket %q failed after %d attempts: %v", cfg.S3Bucket, attempt, berr)
			break
		} else {
			log.Printf("waiting for S3 store (%s), bucket %q not ready (attempt %d): %v", cfg.S3Endpoint, cfg.S3Bucket, attempt, berr)
			time.Sleep(2 * time.Second)
		}
	}

	// Initialize JWKS for token validation — only needed in keycloak mode.
	var jwks *keyfunc.JWKS
	if cfg.AuthMode == "static" {
		log.Printf("Auth mode: static (%d token(s) configured) — Keycloak disabled", len(cfg.StaticTokens))
	} else {
		jwks, err = keyfunc.Get(cfg.KeycloakJWKS, keyfunc.Options{
			RefreshInterval: 15 * time.Minute,
			RefreshErrorHandler: func(err error) {
				log.Printf("JWKS refresh error: %v", err)
			},
		})
		if err != nil {
			log.Printf("Warning: JWKS init failed (Keycloak may not be ready): %v", err)
		}
	}

	// presignClient generates download URLs the consumer can actually resolve.
	// When S3_PUBLIC_ENDPOINT is set (and differs), build a second client
	// against it. Region is pinned so presigning never makes a (doomed) bucket-
	// location call to that unreachable endpoint. Otherwise reuse the main client.
	presignClient := s3Client
	if cfg.S3PublicEndpoint != "" &&
		(cfg.S3PublicEndpoint != cfg.S3Endpoint || cfg.S3PublicUseSSL != cfg.S3UseSSL) {
		pc, perr := minio.New(cfg.S3PublicEndpoint, &minio.Options{
			Creds:  credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""),
			Secure: cfg.S3PublicUseSSL,
			Region: cfg.S3Region, // skip the bucket-location lookup
		})
		if perr != nil {
			log.Fatalf("Failed to create S3 presign client: %v", perr)
		}
		presignClient = pc
		log.Printf("Presigned URLs use public endpoint %s (ssl=%t)", cfg.S3PublicEndpoint, cfg.S3PublicUseSSL)
	}

	srv := &Server{
		config:        cfg,
		s3Client:      s3Client,
		presignClient: presignClient,
		jwks:          jwks,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/.well-known/terraform.json", srv.handleServiceDiscovery)
	mux.HandleFunc("/v1/modules/", srv.handleModules)
	mux.HandleFunc("/v1/catalog", srv.handleCatalog)
	mux.HandleFunc("/m/", srv.handleDirectModule)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "ok")
	})

	log.Printf("Registry API listening on %s (domain: %s)", cfg.ListenAddr, cfg.Domain)
	if err := http.ListenAndServe(cfg.ListenAddr, mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// handleServiceDiscovery returns the Terraform service discovery JSON.
// This tells Terraform where to find modules and how to authenticate.
func (s *Server) handleServiceDiscovery(w http.ResponseWriter, r *http.Request) {
	discovery := ServiceDiscovery{
		Modules: "/v1/modules/",
	}
	// Only advertise the OAuth login flow in keycloak mode. In static mode the
	// consumer supplies the token directly (credentials.tfrc.json or the
	// TF_TOKEN_<host> env var), so there is no login endpoint.
	if s.config.AuthMode != "static" {
		discovery.Login = &LoginConfig{
			Authz:      fmt.Sprintf("https://auth.%s/realms/compliance/protocol/openid-connect/auth", s.config.Domain),
			Client:     "terraform-cli",
			GrantTypes: []string{"authz_code"},
			Ports:      []int{10000, 10010},
			Token:      fmt.Sprintf("https://auth.%s/realms/compliance/protocol/openid-connect/token", s.config.Domain),
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	json.NewEncoder(w).Encode(discovery)
}

// handleModules routes to versions or download based on the path
func (s *Server) handleModules(w http.ResponseWriter, r *http.Request) {
	// Extract framework from Host header subdomain
	// e.g., "cis.conformer.local" -> "cis"
	framework := s.extractFramework(r.Host)
	if framework == "" {
		http.Error(w, "Invalid framework subdomain", http.StatusBadRequest)
		return
	}

	// Validate Bearer token
	claims, err := s.validateToken(r)
	if err != nil {
		http.Error(w, fmt.Sprintf("Unauthorized: %v", err), http.StatusUnauthorized)
		return
	}

	// Check framework entitlement from token claims
	if !s.hasFrameworkEntitlement(claims, framework) {
		http.Error(w, fmt.Sprintf("Forbidden: no entitlement for framework %q", framework), http.StatusForbidden)
		return
	}

	// Parse path: /v1/modules/{namespace}/{name}/{provider}/versions
	//         or: /v1/modules/{namespace}/{name}/{provider}/{version}/download
	path := strings.TrimPrefix(r.URL.Path, "/v1/modules/")
	parts := strings.Split(strings.TrimSuffix(path, "/"), "/")

	switch {
	case len(parts) == 4 && parts[3] == "versions":
		s.handleListVersions(w, r, parts[0], parts[1], parts[2], framework)
	case len(parts) == 5 && parts[4] == "download":
		s.handleDownload(w, r, parts[0], parts[1], parts[2], parts[3], framework)
	default:
		http.Error(w, "Not found", http.StatusNotFound)
	}
}

// handleListVersions lists available versions for a module+framework from the S3 store
func (s *Server) handleListVersions(w http.ResponseWriter, r *http.Request, namespace, name, provider, framework string) {
	ctx := r.Context()

	// In dynamic mode the upstream registry is authoritative for which versions
	// exist — proxy its list so any version can be requested (and built on the
	// subsequent download). Fall back to the S3 listing if upstream fails.
	if s.config.DynamicBuild {
		if body, err := fetchUpstreamVersions(ctx, s.config.UpstreamRegistry, namespace, name, provider); err == nil {
			w.Header().Set("Content-Type", "application/json")
			w.Write(body)
			return
		} else {
			log.Printf("upstream versions fallback for %s/%s/%s: %v", namespace, name, provider, err)
		}
	}

	prefix := fmt.Sprintf("%s/%s/%s/%s/", namespace, name, provider, framework)

	var versions []ModuleVersion
	for obj := range s.s3Client.ListObjects(ctx, s.config.S3Bucket, minio.ListObjectsOptions{
		Prefix:    prefix,
		Recursive: false,
	}) {
		if obj.Err != nil {
			log.Printf("Error listing objects: %v", obj.Err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		// Key format: {ns}/{mod}/{provider}/{framework}/{version}.zip
		key := strings.TrimPrefix(obj.Key, prefix)
		version := strings.TrimSuffix(key, ".zip")
		if version != "" && !strings.Contains(version, "/") {
			versions = append(versions, ModuleVersion{Version: version})
		}
	}

	if len(versions) == 0 {
		http.Error(w, "Module not found", http.StatusNotFound)
		return
	}

	resp := ModuleVersions{
		Modules: []ModuleVersionList{{Versions: versions}},
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// handleDownload generates a presigned S3 URL and returns it via x-terraform-get
func (s *Server) handleDownload(w http.ResponseWriter, r *http.Request, namespace, name, provider, version, framework string) {
	objectKey := fmt.Sprintf("%s/%s/%s/%s/%s.zip", namespace, name, provider, framework, version)

	// Check object exists
	_, err := s.s3Client.StatObject(r.Context(), s.config.S3Bucket, objectKey, minio.StatObjectOptions{})
	if err != nil {
		errResp := minio.ToErrorResponse(err)
		if errResp.Code != "NoSuchKey" {
			log.Printf("Error checking object %s: %v", objectKey, err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		// Cache miss. Without dynamic build, nothing more to do.
		if !s.config.DynamicBuild {
			http.Error(w, "Version not found", http.StatusNotFound)
			return
		}

		// Fetch from upstream + patch for this framework, then re-check.
		if berr := s.ensureBuilt(r.Context(), namespace, name, provider, version, framework, "", objectKey); berr != nil {
			http.Error(w, fmt.Sprintf("Dynamic build failed: %v", berr), http.StatusBadGateway)
			return
		}
		if _, serr := s.s3Client.StatObject(r.Context(), s.config.S3Bucket, objectKey, minio.StatObjectOptions{}); serr != nil {
			log.Printf("object %s missing after build: %v", objectKey, serr)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
	}

	// Generate presigned URL (10 min expiry)
	presignedURL, err := s.presignClient.PresignedGetObject(context.Background(),
		s.config.S3Bucket, objectKey, 10*time.Minute, nil)
	if err != nil {
		log.Printf("Error generating presigned URL: %v", err)
		http.Error(w, "Internal error", http.StatusInternalServerError)
		return
	}

	// Terraform expects 204 with X-Terraform-Get header
	w.Header().Set("X-Terraform-Get", presignedURL.String())
	w.WriteHeader(http.StatusNoContent)
}

// handleDirectModule serves the go-getter "direct" mode (ADR-009): an ad-hoc
// transformation set and/or a framework bundle, OPEN (no token, no entitlement).
// The consumer writes a go-getter http source, not a registry source, so the
// selection rides a real query string. Either or both of framework/transformation:
//
//	source = "https://<domain>/m/<ns>/<name>/<provider>?version=X&transformation=tags,destroy"
//	source = "https://<domain>/m/<ns>/<name>/<provider>?version=X&framework=cis&transformation=tags,destroy"
//
// A framework expands to its unit bundle; the ad-hoc units are applied on top.
// Open by design — composing more units only hardens, never weakens (ADR-012).
//
// We build (always, ad-hoc sets are never pre-baked), cache under a canonical
// profile key, and return X-Terraform-Get pointing at the presigned .zip so
// go-getter (http getter, dir mode) follows it and unpacks the archive.
func (s *Server) handleDirectModule(w http.ResponseWriter, r *http.Request) {
	if !s.config.DirectMode {
		http.Error(w, "Direct transformation mode disabled", http.StatusNotFound)
		return
	}

	// Path: /m/{namespace}/{name}/{provider}
	path := strings.TrimPrefix(r.URL.Path, "/m/")
	parts := strings.Split(strings.TrimSuffix(path, "/"), "/")
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
		http.Error(w, "Expected /m/{namespace}/{name}/{provider}?version=&transformation=", http.StatusBadRequest)
		return
	}
	namespace, name, provider := parts[0], parts[1], parts[2]

	version := r.URL.Query().Get("version")
	if version == "" {
		http.Error(w, "missing required query param: version", http.StatusBadRequest)
		return
	}
	transforms := canonicalTransforms(r.URL.Query().Get("transformation"))

	// Optional framework: compose its unit bundle with the ad-hoc transformations
	// (the build engine appends TRANSFORMATIONS after the framework's units). This
	// stays OPEN — no token, no entitlement — because composing more units can
	// only harden, never weaken. Entitlement lives only on the registry path.
	framework := ""
	if fwRaw := r.URL.Query().Get("framework"); fwRaw != "" {
		if !isSafeName(fwRaw) {
			http.Error(w, "invalid framework query param (expected [A-Za-z0-9_-])", http.StatusBadRequest)
			return
		}
		framework = mapFramework(fwRaw)
	}

	if framework == "" && len(transforms) == 0 {
		http.Error(w, "need at least one of: framework, transformation (comma-separated, [A-Za-z0-9_-])", http.StatusBadRequest)
		return
	}

	// Canonical cache key. framework-only reuses the registry path's cache entry
	// ({framework}); framework+units and units-only get distinct, order-stable
	// keys (tags,destroy == destroy,tags).
	var profile string
	switch {
	case framework != "" && len(transforms) > 0:
		profile = framework + ".plus." + strings.Join(transforms, "-")
	case framework != "":
		profile = framework
	default:
		profile = "set." + strings.Join(transforms, "-")
	}
	objectKey := fmt.Sprintf("%s/%s/%s/%s/%s.zip", namespace, name, provider, profile, version)

	buildFramework := framework
	if buildFramework == "" {
		buildFramework = "none"
	}

	// Build on miss (these profiles are never pre-built).
	if _, err := s.s3Client.StatObject(r.Context(), s.config.S3Bucket, objectKey, minio.StatObjectOptions{}); err != nil {
		errResp := minio.ToErrorResponse(err)
		if errResp.Code != "NoSuchKey" {
			log.Printf("Error checking object %s: %v", objectKey, err)
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}
		if berr := s.ensureBuilt(r.Context(), namespace, name, provider, version, buildFramework, strings.Join(transforms, ","), objectKey); berr != nil {
			http.Error(w, fmt.Sprintf("Build failed: %v", berr), http.StatusBadGateway)
			return
		}
	}

	presignedURL, err := s.presignClient.PresignedGetObject(context.Background(),
		s.config.S3Bucket, objectKey, 10*time.Minute, nil)
	if err != nil {
		log.Printf("Error generating presigned URL: %v", err)
		http.Error(w, "Internal error", http.StatusInternalServerError)
		return
	}

	// go-getter (http source, dir mode) follows X-Terraform-Get to the archive.
	// The presigned URL path ends in .zip, so go-getter detects + unpacks it.
	w.Header().Set("X-Terraform-Get", presignedURL.String())
	w.WriteHeader(http.StatusOK)
}

// canonicalTransforms parses, sanitizes, dedupes, and SORTS a comma-separated
// transformation list. Names become directory names under transformations/ and
// flow into the build via an env var, so the charset is restricted to
// [A-Za-z0-9_-] to prevent path traversal / shell injection.
func canonicalTransforms(raw string) []string {
	seen := map[string]bool{}
	var out []string
	for _, t := range strings.Split(raw, ",") {
		t = strings.TrimSpace(t)
		if t == "" || seen[t] || !isSafeName(t) {
			continue
		}
		seen[t] = true
		out = append(out, t)
	}
	sort.Strings(out)
	return out
}

// isSafeName reports whether s is a safe transformation/dir name: non-empty and
// only [A-Za-z0-9_-].
func isSafeName(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

// extractFramework pulls the framework name from the Host header subdomain
func (s *Server) extractFramework(host string) string {
	// Strip port if present
	if idx := strings.LastIndex(host, ":"); idx != -1 {
		host = host[:idx]
	}
	// e.g., "cis.conformer.local" -> "cis"
	suffix := "." + s.config.Domain
	if !strings.HasSuffix(host, suffix) {
		return ""
	}
	framework := strings.TrimSuffix(host, suffix)
	if framework == "" || strings.Contains(framework, ".") {
		return ""
	}
	return mapFramework(framework)
}

// frameworkMap maps friendly framework names (subdomains / ?framework=) to the
// storage-path / manifest name (frameworks/<path>.hcl).
var frameworkMap = map[string]string{
	"cis":      "cis_v600",
	"iso27001": "iso27001",
	"soc2":     "soc2",
	"hipaa":    "hipaa",
	"pci":      "pci_dss",
	"nist":     "nist_800_53",
}

// mapFramework resolves a friendly framework name to its storage path; unknown
// names pass through verbatim (the build fails later if no manifest exists).
func mapFramework(name string) string {
	if mapped, ok := frameworkMap[name]; ok {
		return mapped
	}
	return name
}

// validateToken validates the Bearer token. In keycloak mode it verifies the
// JWT against the JWKS; in static mode it looks the token up in the configured
// set and returns synthetic claims carrying that token's entitled frameworks.
func (s *Server) validateToken(r *http.Request) (jwt.MapClaims, error) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return nil, fmt.Errorf("missing Authorization header")
	}
	tokenStr := strings.TrimPrefix(auth, "Bearer ")
	if tokenStr == auth {
		return nil, fmt.Errorf("invalid Authorization format")
	}

	if s.config.AuthMode == "static" {
		frameworks, ok := s.config.StaticTokens[tokenStr]
		if !ok {
			return nil, fmt.Errorf("unknown token")
		}
		fwAny := make([]interface{}, len(frameworks))
		for i, f := range frameworks {
			fwAny[i] = f
		}
		return jwt.MapClaims{"frameworks": fwAny}, nil
	}

	if s.jwks == nil {
		return nil, fmt.Errorf("JWKS not initialized")
	}

	token, err := jwt.Parse(tokenStr, s.jwks.Keyfunc,
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithIssuer(s.config.KeycloakIssuer),
	)
	if err != nil {
		return nil, fmt.Errorf("token validation failed: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}
	return claims, nil
}

// hasFrameworkEntitlement checks if the token has access to the requested framework.
// Keycloak encodes entitled frameworks as a "frameworks" claim (list of strings).
func (s *Server) hasFrameworkEntitlement(claims jwt.MapClaims, framework string) bool {
	// Check "realm_access.roles" or a custom "frameworks" claim
	if frameworks, ok := claims["frameworks"]; ok {
		switch f := frameworks.(type) {
		case []interface{}:
			for _, v := range f {
				if str, ok := v.(string); ok && str == framework {
					return true
				}
			}
		}
		return false
	}

	// Fallback: check realm roles
	if realmAccess, ok := claims["realm_access"].(map[string]interface{}); ok {
		if roles, ok := realmAccess["roles"].([]interface{}); ok {
			for _, role := range roles {
				if str, ok := role.(string); ok && str == "framework:"+framework {
					return true
				}
			}
		}
	}

	return false
}

// Ensure rsa import is used (for JWKS)
var _ *rsa.PublicKey

func envOrDefault(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}

// parseStaticTokens parses the STATIC_TOKENS env var into a token->frameworks
// map. Format: "token1=cis_v600,soc2;token2=iso27001" (entries ';'-separated,
// token and CSV framework list split by '='). Framework names are the storage
// paths (cis_v600, iso27001, soc2), matching the registry object layout.
func parseStaticTokens(raw string) map[string][]string {
	out := map[string][]string{}
	for _, entry := range strings.Split(raw, ";") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		kv := strings.SplitN(entry, "=", 2)
		if len(kv) != 2 {
			continue
		}
		token := strings.TrimSpace(kv[0])
		var frameworks []string
		for _, f := range strings.Split(kv[1], ",") {
			if f = strings.TrimSpace(f); f != "" {
				frameworks = append(frameworks, f)
			}
		}
		if token != "" {
			out[token] = frameworks
		}
	}
	return out
}
