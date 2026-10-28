#!/usr/bin/env node
// Copyright 2026 Google LLC
// SPDX-License-Identifier: Apache-2.0
//
// Generalized HTTP, Cache-Guard, and Container Image verifier driven by per-app
// expectations.json files.
//
// Usage:
//   node scripts/verify.mjs <app-dir-or-name> [<base-url>] [--image=<tag>] [--container=<id>]
//   node scripts/verify.mjs --app=apps/single-app --url=http://127.0.0.1:18080

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');

const CDN_HEADERS = [
  'cdn-cache-control',
  'cloudflare-cdn-cache-control',
  'vercel-cdn-cache-control',
  'surrogate-control',
];

function parseArgs(argv) {
  let appArg = null;
  let urlArg = null;
  let expectationsPath = null;
  let imageTag = null;
  let containerId = null;
  let buildIdArg = null;
  let expectApiData = null;
  const positional = [];

  for (const a of argv.slice(2)) {
    if (a.startsWith('--app=')) {
      appArg = a.slice('--app='.length);
    } else if (a.startsWith('--url=')) {
      urlArg = a.slice('--url='.length);
    } else if (a.startsWith('--expectations=')) {
      expectationsPath = a.slice('--expectations='.length);
    } else if (a.startsWith('--image=')) {
      imageTag = a.slice('--image='.length);
    } else if (a.startsWith('--container=')) {
      containerId = a.slice('--container='.length);
    } else if (a.startsWith('--build-id=')) {
      buildIdArg = a.slice('--build-id='.length);
    } else if (a.startsWith('--expect-api-data=')) {
      expectApiData = a.slice('--expect-api-data='.length);
    } else if (!a.startsWith('--')) {
      positional.push(a);
    }
  }

  for (const p of positional) {
    if (/^https?:\/\//i.test(p)) {
      if (!urlArg) urlArg = p;
    } else if (!appArg) {
      appArg = p;
    } else if (!urlArg) {
      urlArg = p;
    }
  }

  return {
    appArg,
    baseUrl: (urlArg || 'http://127.0.0.1:18080').replace(/\/+$/, ''),
    expectationsPath,
    imageTag,
    containerId,
    buildIdArg,
    expectApiData,
  };
}

function resolveAppDir(appArg) {
  if (!appArg) return null;
  const candidates = [
    path.resolve(appArg),
    path.resolve(repoRoot, appArg),
    path.resolve(repoRoot, 'apps', appArg),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c) && fs.statSync(c).isDirectory()) {
      return c;
    }
  }
  return null;
}

async function httpRequest(baseUrl, routePath, method = 'GET', headers = {}) {
  const url = `${baseUrl}${routePath.startsWith('/') ? routePath : '/' + routePath}`;
  let res;
  let lastErr;
  for (let attempt = 1; attempt <= 20; attempt++) {
    try {
      res = await fetch(url, {
        method,
        headers,
        redirect: 'manual',
      });
      break;
    } catch (err) {
      lastErr = err;
      if (attempt === 20) throw err;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  if (!res) throw lastErr;
  const buf = Buffer.from(await res.arrayBuffer());
  const lowerHeaders = {};
  for (const [k, v] of res.headers.entries()) {
    lowerHeaders[k.toLowerCase()] = v;
  }
  return {
    url,
    status: res.status,
    headers: lowerHeaders,
    text: buf.toString('utf8'),
    bytes: buf.length,
  };
}

function assertGuardedCacheControl(cc, label) {
  assert.ok(cc, `${label}: missing Cache-Control header`);
  assert.ok(cc.includes('private'), `${label}: expected 'private' in Cache-Control, got '${cc}'`);
  assert.ok(cc.includes('no-cache'), `${label}: expected 'no-cache' in Cache-Control, got '${cc}'`);
  assert.ok(cc.includes('no-store'), `${label}: expected 'no-store' in Cache-Control, got '${cc}'`);
  assert.ok(cc.includes('max-age=0'), `${label}: expected 'max-age=0' in Cache-Control, got '${cc}'`);
  assert.ok(
    cc.includes('must-revalidate'),
    `${label}: expected 'must-revalidate' in Cache-Control, got '${cc}'`
  );
  assert.ok(!cc.includes('public'), `${label}: must not contain 'public' in Cache-Control, got '${cc}'`);
  assert.ok(
    !cc.includes('s-maxage'),
    `${label}: must not contain 's-maxage' in Cache-Control, got '${cc}'`
  );
}

function assertNoCdnHeaders(headers, label) {
  for (const h of CDN_HEADERS) {
    assert.equal(headers[h], undefined, `${label}: expected ${h} to be stripped, got '${headers[h]}'`);
  }
}

function assertCacheControlRule(ccRule, headers, label) {
  if (!ccRule) return;
  const cc = headers['cache-control'] || '';

  if (ccRule === 'guarded') {
    assertGuardedCacheControl(cc, label);
    assertNoCdnHeaders(headers, label);
    return;
  }

  if (ccRule === 'unguarded-s-maxage' || ccRule === 's-maxage') {
    assert.ok(cc.includes('s-maxage'), `${label}: expected 's-maxage' in Cache-Control, got '${cc}'`);
    assert.ok(
      cc.includes('max-age=0'),
      `${label}: expected 'max-age=0' appended alongside 's-maxage', got '${cc}'`
    );
    assert.ok(
      !cc.includes('private'),
      `${label}: expected unguarded Cache-Control without 'private', got '${cc}'`
    );
    return;
  }

  if (ccRule === 'unguarded') {
    if (cc.includes('s-maxage')) {
      assert.ok(
        cc.includes('max-age=0'),
        `${label}: expected 'max-age=0' appended when 's-maxage' is present, got '${cc}'`
      );
    }
    return;
  }

  if (typeof ccRule === 'string') {
    assert.ok(
      cc.includes(ccRule),
      `${label}: expected Cache-Control to include '${ccRule}', got '${cc}'`
    );
    return;
  }

  if (typeof ccRule === 'object') {
    for (const inc of ccRule.includes || []) {
      assert.ok(cc.includes(inc), `${label}: expected Cache-Control to include '${inc}', got '${cc}'`);
    }
    for (const exc of ccRule.excludes || []) {
      assert.ok(
        !cc.includes(exc),
        `${label}: expected Cache-Control not to include '${exc}', got '${cc}'`
      );
    }
  }
}

function getByDottedPath(obj, dotted) {
  return dotted.split('.').reduce((acc, part) => (acc == null ? undefined : acc[part]), obj);
}

async function resolveBuildId({ buildIdArg, appDir, containerId, baseUrl, expectations }) {
  if (buildIdArg) return buildIdArg;

  if (appDir) {
    const candidates = [
      path.join(appDir, '.next', 'BUILD_ID'),
      path.join(appDir, 'apps', 'web', '.next', 'BUILD_ID'),
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) {
        return fs.readFileSync(c, 'utf8').trim();
      }
    }
  }

  if (containerId) {
    try {
      const out = execFileSync(
        'docker',
        [
          'exec',
          containerId,
          'sh',
          '-c',
          'cat /workspace/.next/standalone/.next/BUILD_ID /workspace/.next/BUILD_ID 2>/dev/null | head -n 1',
        ],
        { encoding: 'utf8' }
      ).trim();
      if (out) return out;
    } catch {
      // Ignore and fall back to HTTP probe.
    }
  }

  const probePaths = [];
  if (expectations.buildIdProbePath) probePaths.push(expectations.buildIdProbePath);
  for (const r of expectations.routes || []) {
    if (r.path && !r.path.includes('<buildId>') && !r.path.includes('{{BUILD_ID}}') && !r.path.startsWith('/_next/')) {
      probePaths.push(r.path);
    }
  }
  probePaths.push('/');

  for (const p of probePaths) {
    try {
      const res = await httpRequest(baseUrl, p);
      const m =
        res.text.match(/"buildId"\s*:\s*"([^"]+)"/) ||
        res.text.match(/\/_next\/static\/([A-Za-z0-9_-]{10,})\/_buildManifest\.js/);
      if (m && m[1]) return m[1];
    } catch {
      // Continue trying next probe path.
    }
  }

  return null;
}

function verifyImageExpectations(imageExp, { imageTag, containerId }) {
  const results = [];
  if (!imageExp) return results;

  for (const manual of imageExp.manualChecks || []) {
    results.push({
      check: `image:${manual.name || 'manual'}`,
      status: 'manual',
      description: manual.description || '',
    });
  }

  const target = imageTag || containerId;
  if (!target) return results;

  if (imageExp.labels) {
    const raw = execFileSync('docker', ['inspect', target, '--format', '{{json .Config.Labels}}'], {
      encoding: 'utf8',
    }).trim();
    const labels = JSON.parse(raw) || {};
    for (const [k, expectedVal] of Object.entries(imageExp.labels)) {
      if (expectedVal === null) {
        assert.equal(
          labels[k],
          undefined,
          `Expected image label '${k}' to be absent, got '${labels[k]}'`
        );
      } else {
        assert.equal(
          labels[k],
          expectedVal,
          `Expected image label '${k}=${expectedVal}', got '${labels[k]}'`
        );
      }
    }
    results.push({ check: 'image:labels', status: 'pass', labels: imageExp.labels });
  }

  if (imageExp.noFilesMatching && imageExp.noFilesMatching.length > 0) {
    for (const suffix of imageExp.noFilesMatching) {
      let count = 0;
      if (containerId) {
        const out = execFileSync(
          'docker',
          [
            'exec',
            containerId,
            '/layers/google.nodejs.runtime/node/bin/node',
            '-e',
            'const fs=require("fs");const s=process.argv[1];console.log(fs.readdirSync("/workspace",{recursive:true}).filter(f=>String(f).endsWith(s)).length);',
            suffix,
          ],
          { encoding: 'utf8' }
        ).trim();
        count = Number(out);
      } else if (imageTag) {
        const out = execFileSync(
          'docker',
          [
            'run',
            '--rm',
            '--entrypoint',
            '/layers/google.nodejs.runtime/node/bin/node',
            imageTag,
            '-e',
            'const fs=require("fs");const s=process.argv[1];console.log(fs.readdirSync("/workspace",{recursive:true}).filter(f=>String(f).endsWith(s)).length);',
            suffix,
          ],
          { encoding: 'utf8' }
        ).trim();
        count = Number(out);
      }
      assert.equal(count, 0, `Expected 0 files ending with '${suffix}' in /workspace, found ${count}`);
      results.push({ check: `image:noFilesMatching(${suffix})`, status: 'pass', count: 0 });
    }
  }

  return results;
}

async function runRouteCheck(route, { baseUrl, buildId, expectApiData }) {
  const mode =
    route.mode ||
    route.expectation ||
    (route.knownGap ? 'known-gap' : route.manual ? 'manual' : 'pass');

  if (mode === 'manual') {
    return {
      check: route.name || `${route.method || 'GET'} ${route.path}`,
      status: 'manual',
      note: route.note || route.description || 'Manual verification required',
    };
  }

  let resolvedPath = route.path;
  if (resolvedPath.includes('<buildId>') || resolvedPath.includes('{{BUILD_ID}}')) {
    assert.ok(buildId, `Route '${resolvedPath}' requires <buildId>, but buildId could not be resolved`);
    resolvedPath = resolvedPath.replaceAll('<buildId>', buildId).replaceAll('{{BUILD_ID}}', buildId);
  }

  const label = route.name || `${route.method || 'GET'} ${resolvedPath}`;
  const res = await httpRequest(baseUrl, resolvedPath, route.method || 'GET', route.requestHeaders || {});

  const performAssertions = () => {
    const expectedStatuses = Array.isArray(route.status) ? route.status : [route.status ?? 200];
    assert.ok(
      expectedStatuses.includes(res.status),
      `${label}: expected status ${expectedStatuses.join('|')}, got ${res.status}`
    );

    if (route.expectGuarded || route.guarded) {
      assertCacheControlRule('guarded', res.headers, label);
    } else if (route.cacheControl) {
      assertCacheControlRule(route.cacheControl, res.headers, label);
    }

    if (route.expectCdnHeadersStripped) {
      assertNoCdnHeaders(res.headers, label);
    }

    if (route.responseHeaders || route.headers) {
      for (const [hk, hv] of Object.entries(route.responseHeaders || route.headers)) {
        const actual = res.headers[hk.toLowerCase()];
        if (hv === null) {
          assert.equal(actual, undefined, `${label}: expected header '${hk}' to be absent, got '${actual}'`);
        } else if (typeof hv === 'object' && hv.includes) {
          assert.ok(
            actual && actual.includes(hv.includes),
            `${label}: expected header '${hk}' to include '${hv.includes}', got '${actual}'`
          );
        } else {
          assert.equal(
            actual,
            String(hv),
            `${label}: expected header '${hk}=${hv}', got '${actual}'`
          );
        }
      }
    }

    const bodyContains = Array.isArray(route.bodyContains)
      ? route.bodyContains
      : route.bodyContains
        ? [route.bodyContains]
        : [];
    for (const needle of bodyContains) {
      assert.ok(res.text.includes(needle), `${label}: response body missing '${needle}'`);
    }

    const bodyExcludes = Array.isArray(route.bodyExcludes)
      ? route.bodyExcludes
      : route.bodyExcludes
        ? [route.bodyExcludes]
        : [];
    for (const needle of bodyExcludes) {
      assert.ok(!res.text.includes(needle), `${label}: response body unexpectedly contained '${needle}'`);
    }

    if (route.jsonEquals !== undefined) {
      const parsed = JSON.parse(res.text);
      assert.deepEqual(parsed, route.jsonEquals, `${label}: JSON mismatch`);
    }

    if (route.jsonContains) {
      const parsed = JSON.parse(res.text);
      for (const [k, v] of Object.entries(route.jsonContains)) {
        const actual = getByDottedPath(parsed, k);
        if (v && typeof v === 'object' && v.includes) {
          assert.ok(
            typeof actual === 'string' && actual.includes(v.includes),
            `${label}: expected JSON '${k}' to include '${v.includes}', got '${JSON.stringify(actual)}'`
          );
        } else {
          assert.deepEqual(actual, v, `${label}: expected JSON '${k}'=${JSON.stringify(v)}, got ${JSON.stringify(actual)}`);
        }
      }
    }

    if (resolvedPath === '/api/hello' && expectApiData && expectApiData !== 'any') {
      const parsed = JSON.parse(res.text);
      if (expectApiData === 'ok') {
        assert.deepEqual(parsed.data, { computedData: 'secret-42' });
      } else if (expectApiData === 'enoent') {
        assert.ok(parsed.data?.error?.includes('ENOENT'), `Expected ENOENT on /api/hello, got ${res.text}`);
      }
    }
  };

  if (mode === 'known-gap') {
    try {
      performAssertions();
      return {
        check: label,
        path: resolvedPath,
        status: 'known-gap',
        httpStatus: res.status,
        cacheControl: res.headers['cache-control'] || null,
        note: route.note || 'Known gap verified',
      };
    } catch (err) {
      return {
        check: label,
        path: resolvedPath,
        status: 'known-gap',
        httpStatus: res.status,
        cacheControl: res.headers['cache-control'] || null,
        note: route.note || err.message,
      };
    }
  }

  performAssertions();
  return {
    check: label,
    path: resolvedPath,
    status: 'pass',
    httpStatus: res.status,
    cacheControl: res.headers['cache-control'] || null,
  };
}

async function main() {
  const opts = parseArgs(process.argv);
  const appDir = resolveAppDir(opts.appArg);
  const expFile =
    opts.expectationsPath ||
    (appDir ? path.join(appDir, 'expectations.json') : null);

  if (!expFile || !fs.existsSync(expFile)) {
    throw new Error(
      `expectations.json not found. Pass an app directory (e.g. apps/single-app) or --expectations=<path>.`
    );
  }

  const expectations = JSON.parse(fs.readFileSync(expFile, 'utf8'));
  const results = [];

  // 1. Image / container checks (if --image or --container supplied, or manualChecks defined).
  const imageResults = verifyImageExpectations(expectations.image, opts);
  results.push(...imageResults);

  // 2. Runtime HTTP & Cache-Guard checks.
  if (!expectations.skipRuntime) {
    const routes = expectations.routes || [];
    const needsBuildId = routes.some(
      (r) => r.path && (r.path.includes('<buildId>') || r.path.includes('{{BUILD_ID}}'))
    );
    const buildId = needsBuildId
      ? await resolveBuildId({ ...opts, appDir, expectations })
      : opts.buildIdArg;

    for (const route of routes) {
      const r = await runRouteCheck(route, {
        baseUrl: opts.baseUrl,
        buildId,
        expectApiData: opts.expectApiData,
      });
      results.push(r);
    }
  } else {
    results.push({
      check: 'runtime',
      status: expectations.mode || 'pass',
      note: expectations.skipRuntimeReason || 'Runtime HTTP check skipped by expectations.json',
    });
  }

  const hasKnownGap =
    expectations.mode === 'known-gap' || results.some((r) => r.status === 'known-gap');
  const hasManual =
    expectations.mode === 'manual' || results.some((r) => r.status === 'manual');
  const overallStatus = hasKnownGap ? 'known-gap' : hasManual ? 'pass (with manual)' : 'pass';

  console.log(
    JSON.stringify(
      {
        ok: true,
        app: expectations.name || (appDir ? path.basename(appDir) : 'unknown'),
        status: overallStatus,
        baseUrl: expectations.skipRuntime ? null : opts.baseUrl,
        results,
      },
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error('VERIFY FAILED:', err.message || err);
  process.exit(1);
});
