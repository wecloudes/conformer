package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/minio/minio-go/v7"
)

// Catalog is the /v1/catalog response: what this registry can serve, so a
// consumer can discover available frameworks, transformation units, and the
// modules already hardened + cached. Open (discovery, no token).
type Catalog struct {
	Domain          string             `json:"domain"`
	Frameworks      []FrameworkInfo    `json:"frameworks"`
	Transformations []string           `json:"transformations"`
	CachedModules   []CachedModuleInfo `json:"cached_modules"`
}

type FrameworkInfo struct {
	Name            string   `json:"name"`      // storage/manifest name, e.g. cis_v600
	Subdomain       string   `json:"subdomain"` // friendly subdomain, e.g. cis
	Description     string   `json:"description"`
	Transformations []string `json:"transformations"`
}

type CachedModuleInfo struct {
	Source   string   `json:"source"` // ns/name/provider
	Profiles []string `json:"profiles"`
	Versions []string `json:"versions"`
}

var descRe = regexp.MustCompile(`(?m)^\s*description\s*=\s*"([^"]*)"`)

// frameworksDir / transformsDir are siblings of PatchesDir (the assets anchor).
func (s *Server) frameworksDir() string {
	return filepath.Join(filepath.Dir(s.config.PatchesDir), "frameworks")
}
func (s *Server) transformsDir() string {
	return filepath.Join(filepath.Dir(s.config.PatchesDir), "transformations")
}

// reverseFrameworkMap maps a storage name back to its friendly subdomain.
func reverseFrameworkName(storage string) string {
	for friendly, mapped := range frameworkMap {
		if mapped == storage {
			return friendly
		}
	}
	return storage
}

// parseFrameworkManifest extracts description + the transformations list from a
// frameworks/<fw>.hcl file (same shape patch-module.sh reads).
func parseFrameworkManifest(path string) (FrameworkInfo, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return FrameworkInfo{}, err
	}
	name := strings.TrimSuffix(filepath.Base(path), ".hcl")
	info := FrameworkInfo{Name: name, Subdomain: reverseFrameworkName(name)}
	if m := descRe.FindSubmatch(b); m != nil {
		info.Description = string(m[1])
	}
	// Extract quoted unit names inside the transformations = [ ... ] array.
	src := string(b)
	if i := strings.Index(src, "transformations"); i >= 0 {
		if open := strings.Index(src[i:], "["); open >= 0 {
			rest := src[i+open:]
			if close := strings.Index(rest, "]"); close >= 0 {
				for _, q := range regexp.MustCompile(`"([A-Za-z0-9_-]+)"`).FindAllStringSubmatch(rest[:close], -1) {
					info.Transformations = append(info.Transformations, q[1])
				}
			}
		}
	}
	return info, nil
}

func (s *Server) handleCatalog(w http.ResponseWriter, r *http.Request) {
	cat := Catalog{Domain: s.config.Domain}

	// Frameworks (from frameworks/*.hcl).
	if entries, err := os.ReadDir(s.frameworksDir()); err == nil {
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".hcl") {
				continue
			}
			if fi, perr := parseFrameworkManifest(filepath.Join(s.frameworksDir(), e.Name())); perr == nil {
				cat.Frameworks = append(cat.Frameworks, fi)
			}
		}
		sort.Slice(cat.Frameworks, func(i, j int) bool { return cat.Frameworks[i].Name < cat.Frameworks[j].Name })
	}

	// Transformation units (top-level dirs under transformations/).
	if entries, err := os.ReadDir(s.transformsDir()); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				cat.Transformations = append(cat.Transformations, e.Name())
			}
		}
		sort.Strings(cat.Transformations)
	}

	// Cached modules (list objects, key = ns/name/provider/profile/version.zip).
	type modAgg struct {
		profiles map[string]bool
		versions map[string]bool
	}
	mods := map[string]*modAgg{}
	for obj := range s.s3Client.ListObjects(r.Context(), s.config.S3Bucket, minio.ListObjectsOptions{Recursive: true}) {
		if obj.Err != nil {
			log.Printf("catalog: list error: %v", obj.Err)
			break
		}
		parts := strings.Split(strings.TrimSuffix(obj.Key, ".zip"), "/")
		if len(parts) != 5 {
			continue
		}
		src := strings.Join(parts[0:3], "/")
		profile, version := parts[3], parts[4]
		if mods[src] == nil {
			mods[src] = &modAgg{profiles: map[string]bool{}, versions: map[string]bool{}}
		}
		mods[src].profiles[profile] = true
		mods[src].versions[version] = true
	}
	for src, agg := range mods {
		cm := CachedModuleInfo{Source: src}
		for p := range agg.profiles {
			cm.Profiles = append(cm.Profiles, p)
		}
		for v := range agg.versions {
			cm.Versions = append(cm.Versions, v)
		}
		sort.Strings(cm.Profiles)
		sort.Strings(cm.Versions)
		cat.CachedModules = append(cat.CachedModules, cm)
	}
	sort.Slice(cat.CachedModules, func(i, j int) bool { return cat.CachedModules[i].Source < cat.CachedModules[j].Source })

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(cat)
}
