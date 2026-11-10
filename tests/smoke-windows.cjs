const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const [decoder, prober, clip, reference, rangeClip] = process.argv.slice(2);
if (![decoder, prober, clip, reference, rangeClip].every(Boolean)) {
    throw new Error('usage: smoke-windows.cjs DECODER PROBER CLIP LINUX_REFERENCE RANGE_CLIP');
}

const expectedMetadata = 'h264,320,180,30/1';
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'evovpeg-windows-'));
const requests = [];
const servers = [];

function run(program, args, expectedExit = 0) {
    return new Promise((resolve, reject) => {
        const child = spawn(program, args, { windowsHide: true });
        const stdout = [];
        const stderr = [];
        const timer = setTimeout(() => child.kill(), 30000);
        child.stdout.on('data', chunk => stdout.push(chunk));
        child.stderr.on('data', chunk => stderr.push(chunk));
        child.on('error', error => {
            clearTimeout(timer);
            reject(error);
        });
        child.on('close', code => {
            clearTimeout(timer);
            const result = { code, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr).toString() };
            if (code !== expectedExit) {
                reject(new Error(`${path.basename(program)} exited ${code}, expected ${expectedExit}: ${result.stderr}`));
            } else {
                resolve(result);
            }
        });
    });
}

function makeCertificate(name, commonName) {
    const key = path.join(work, `${name}.key`);
    const cert = path.join(work, `${name}.pem`);
    const result = spawnSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key,
        '-out', cert, '-days', '1', '-subj', `/CN=${commonName}`,
        '-addext', `subjectAltName=DNS:${commonName},IP:127.0.0.1`,
    ], { windowsHide: true, stdio: 'ignore' });
    if (result.status !== 0) throw new Error(`openssl certificate generation failed (${result.status})`);
    return { key: fs.readFileSync(key), cert: fs.readFileSync(cert), certPath: cert };
}

function serve(request, response) {
    requests.push({ range: request.headers.range || '', marker: request.headers['x-peg-test'] || '' });
    if (request.url === '/redirect') {
        response.writeHead(302, { Location: '/clip.mp4' }).end();
        return;
    }
    if (request.url !== '/clip.mp4') {
        response.writeHead(404).end();
        return;
    }
    const size = fs.statSync(rangeClip).size;
    const range = request.headers.range;
    let start = 0;
    let end = size - 1;
    if (range) {
        const match = /^bytes=(\d+)-(\d*)$/.exec(range);
        if (!match || Number(match[1]) >= size) {
            response.writeHead(416, { 'Content-Range': `bytes */${size}` }).end();
            return;
        }
        start = Number(match[1]);
        if (match[2]) end = Math.min(Number(match[2]), size - 1);
    }
    const headers = { 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1 };
    if (range) headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
    response.writeHead(range ? 206 : 200, headers);
    if (request.method === 'HEAD') response.end();
    else fs.createReadStream(rangeClip, { start, end }).pipe(response);
}

function listen(server) {
    return new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '0.0.0.0', () => resolve(server.address().port));
    });
}

function close(server) {
    return new Promise(resolve => {
        if (!server.listening) return resolve();
        server.close(resolve);
        server.closeAllConnections();
    });
}

async function main() {
    const trusted = makeCertificate('trusted', 'localhost');
    const untrusted = makeCertificate('untrusted', 'localhost');
    const httpServer = http.createServer(serve);
    const httpsServer = https.createServer({ key: trusted.key, cert: trusted.cert }, serve);
    servers.push(httpServer, httpsServer);
    const httpPort = await listen(httpServer);
    const httpsPort = await listen(httpsServer);
    const referenceBytes = fs.readFileSync(reference);
    if (referenceBytes.length !== 5184000) throw new Error(`Linux reference has ${referenceBytes.length} bytes`);

    const localProbe = await run(prober, [
        '-v', 'error', '-select_streams', 'v:0', '-show_entries',
        'stream=codec_name,width,height,r_frame_rate', '-of', 'csv=p=0', clip,
    ]);
    if (localProbe.stdout.toString().trim() !== expectedMetadata) throw new Error(`local probe: ${localProbe.stdout}`);

    const localFrames = await run(decoder, [
        '-nostdin', '-v', 'error', '-threads', '1', '-i', clip, '-frames:v', '60',
        '-an', '-sn', '-pix_fmt', 'yuv420p', '-f', 'rawvideo', 'pipe:1',
    ]);
    if (!localFrames.stdout.equals(referenceBytes)) throw new Error('Windows local frames differ from Linux x64');

    const headers = ['-user_agent', 'peg-smoke', '-headers', 'X-Peg-Test: present\r\n', '-rw_timeout', '15000000'];
    for (const [scheme, host, port, tls] of [
        ['http', '127.0.0.1', httpPort, []],
        ['https', '127.0.0.1', httpsPort, ['-tls_verify', '1', '-ca_file', trusted.certPath]],
    ]) {
        const url = `${scheme}://${host}:${port}/clip.mp4`;
        const probe = await run(prober, [...headers, ...tls, '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=codec_name,width,height,r_frame_rate', '-of', 'csv=p=0', url]);
        if (probe.stdout.toString().trim() !== expectedMetadata) throw new Error(`${scheme} probe: ${probe.stdout}`);
        const remoteFrames = await run(decoder, [
            '-nostdin', '-v', 'error', '-threads', '1', ...headers, ...tls,
            '-seekable', '1', '-ss', '1', '-i', url, '-frames:v', '30',
            '-an', '-sn', '-pix_fmt', 'yuv420p', '-f', 'rawvideo', 'pipe:1',
        ]);
        const localSeek = await run(decoder, [
            '-nostdin', '-v', 'error', '-threads', '1', '-ss', '1', '-i', clip,
            '-frames:v', '30', '-an', '-sn', '-pix_fmt', 'yuv420p', '-f', 'rawvideo', 'pipe:1',
        ]);
        if (!remoteFrames.stdout.equals(localSeek.stdout)) throw new Error(`${scheme} seek frames differ from local`);
    }

    const wrongCaUrl = `https://127.0.0.1:${httpsPort}/clip.mp4`;
    await run(prober, [...headers, '-tls_verify', '1', '-ca_file', untrusted.certPath,
        '-v', 'error', wrongCaUrl], 1);
    await run(prober, [...headers, '-tls_verify', '1', '-ca_file', trusted.certPath,
        '-v', 'error', `https://127.0.0.2:${httpsPort}/clip.mp4`], 1);
    await run(prober, [...headers, '-ca_file', untrusted.certPath, '-v', 'error', wrongCaUrl], 1);

    if (!requests.some(request => /^bytes=[1-9][0-9]*-/.test(request.range))) throw new Error('no HTTP range request observed');
    if (!requests.some(request => request.marker === 'present')) throw new Error('custom HTTP header was not received');
    console.log('[OK] Windows local/HTTP/HTTPS probe, range seek, TLS verification, and Linux frame parity');

    await close(httpServer);
    await close(httpsServer);
}

main().catch(error => {
    console.error(error);
    process.exitCode = 1;
}).finally(async () => {
    await Promise.all(servers.map(close));
    fs.rmSync(work, { recursive: true, force: true });
});