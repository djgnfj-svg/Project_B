// Project_B 웹 빌드 서빙 Worker — 정적 에셋 그대로, index.wasm만 특수 처리.
// Godot wasm(37MB)이 에셋 파일당 25MiB 제한을 넘어 gzip본(index.wasm.gz, ~10MB)을 올려두고,
// 브라우저에는 Content-Encoding: gzip + Content-Type: application/wasm으로 내보낸다
// (encodeBody: "manual" — 런타임이 재압축하지 않고 그대로 통과).

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === "/index.wasm") {
			// If-None-Match만 전달(Range는 의도적으로 미전달 — 부분 gzip 바디 사고 방지),
			// no-cache(재검증 필수) + ETag로 재배포 즉시 반영 — max-age를 주면 로더/pck(에셋 기본
			// 서빙, ETag 재검증)만 갱신되고 wasm은 묵어 버전 스큐가 난다.
			const inm = request.headers.get("If-None-Match");
			const asset = await env.ASSETS.fetch(
				new Request(new URL("/index.wasm.gz", url.origin), {
					headers: inm ? { "If-None-Match": inm } : {},
				}),
			);
			const headers = {
				"Content-Type": "application/wasm",
				"Content-Encoding": "gzip",
				"Cache-Control": "no-cache",
			};
			const etag = asset.headers.get("ETag");
			if (etag) headers["ETag"] = etag;
			if (asset.status === 304) return new Response(null, { status: 304, headers });
			if (!asset.ok) return asset;
			return new Response(asset.body, { encodeBody: "manual", headers });
		}
		return env.ASSETS.fetch(request);
	},
};
