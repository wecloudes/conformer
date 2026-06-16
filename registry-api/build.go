package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/minio/minio-go/v7"
)

// buildTimeout caps a single on-demand build (fetch + patch + upload).
const buildTimeout = 8 * time.Minute

// ensureBuilt guarantees that objectKey exists in the S3 store, building it on demand
// if missing. Concurrent requests for the same key are serialized so the module
// is fetched and patched exactly once.
//
// framework selects the framework rule packs ("none" = skip them). transforms is
// a comma-separated list of composable transformation units to apply (empty in
// the pure-framework path); it is passed to the build via TRANSFORMATIONS so
// patch-module.sh applies transformations/<name>/... on top.
func (s *Server) ensureBuilt(ctx context.Context, namespace, name, provider, version, framework, transforms, objectKey string) error {
	muIface, _ := s.builds.LoadOrStore(objectKey, &sync.Mutex{})
	mu := muIface.(*sync.Mutex)
	mu.Lock()
	defer mu.Unlock()

	// Re-check after acquiring the lock — another request may have built it.
	if _, err := s.s3Client.StatObject(ctx, s.config.S3Bucket, objectKey, minio.StatObjectOptions{}); err == nil {
		return nil
	}

	bctx, cancel := context.WithTimeout(ctx, buildTimeout)
	defer cancel()

	// The script fetches + patches and writes the zip here; Go uploads it via the
	// minio-go SDK (Apache-2.0), so no AGPL mc binary is needed.
	zip, err := os.CreateTemp("", "module-*.zip")
	if err != nil {
		return fmt.Errorf("temp zip: %w", err)
	}
	zipPath := zip.Name()
	zip.Close()
	defer os.Remove(zipPath)

	log.Printf("dynamic build START %s (framework=%s transforms=%q)", objectKey, framework, transforms)
	cmd := exec.CommandContext(bctx, "/bin/bash", s.config.BuildScript,
		namespace, name, provider, version, framework)
	cmd.Env = append(os.Environ(),
		"PATCHES_ROOT="+s.config.PatchesDir,
		"UPSTREAM_REGISTRY="+s.config.UpstreamRegistry,
		"OUT_ZIP="+zipPath,
	)
	if transforms != "" {
		cmd.Env = append(cmd.Env, "TRANSFORMATIONS="+transforms)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("dynamic build FAILED %s: %v\n%s", objectKey, err, out)
		return fmt.Errorf("build failed: %w", err)
	}
	log.Printf("dynamic build OK %s\n%s", objectKey, out)

	if uerr := uploadObject(bctx, s.s3Client, s.config.S3Bucket, objectKey, zipPath); uerr != nil {
		return fmt.Errorf("upload: %w", uerr)
	}
	return nil
}

// ensureBucket creates the bucket if it does not exist.
func ensureBucket(ctx context.Context, mc *minio.Client, bucket string) error {
	exists, err := mc.BucketExists(ctx, bucket)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	return mc.MakeBucket(ctx, bucket, minio.MakeBucketOptions{})
}

// uploadObject puts a local file into the bucket under objectKey.
func uploadObject(ctx context.Context, mc *minio.Client, bucket, objectKey, path string) error {
	if err := ensureBucket(ctx, mc, bucket); err != nil {
		return err
	}
	_, err := mc.FPutObject(ctx, bucket, objectKey, path, minio.PutObjectOptions{ContentType: "application/zip"})
	return err
}

// fetchUpstreamVersions proxies the module-versions list from the upstream
// registry, so Terraform can resolve a version constraint for a module that has
// never been built locally.
func fetchUpstreamVersions(ctx context.Context, registry, namespace, name, provider string) ([]byte, error) {
	url := fmt.Sprintf("https://%s/v1/modules/%s/%s/%s/versions", registry, namespace, name, provider)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("upstream versions returned %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}
