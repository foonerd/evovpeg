const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const path = require('node:path');

const work = process.argv[2];
const clips = process.argv[3];
const files = new Map([
    ['/clip.mp4', path.join(clips, 'flash-h264.mp4')],
    ['/audio.mkv', path.join(clips, 'audio/flash-h264-aac.mkv')],
    ['/tail.mp4', path.join(work, 'tail.mp4')],
]);

function serve(request, response) {
    fs.appendFileSync(path.join(work, 'requests.jsonl'), JSON.stringify({
        url: request.url,
        range: request.headers.range || '',
        agent: request.headers['user-agent'] || '',
        marker: request.headers['x-peg-test'] || '',
    }) + '\n');
    if (request.url === '/redirect') {
        response.writeHead(302, { Location: '/clip.mp4' });
        response.end();
        return;
    }
    if (request.url === '/timeout') return;
    const file = files.get(request.url);
    if (!file) {
        response.writeHead(404);
        response.end();
        return;
    }
    const size = fs.statSync(file).size;
    let start = 0;
    let end = size - 1;
    const range = request.headers.range;
    if (range) {
        const match = /^bytes=(\d+)-(\d*)$/.exec(range);
        if (!match || Number(match[1]) >= size) {
            response.writeHead(416, { 'Content-Range': `bytes */${size}` });
            response.end();
            return;
        }
        start = Number(match[1]);
        if (match[2]) end = Math.min(Number(match[2]), size - 1);
        if (end < start) {
            response.writeHead(416);
            response.end();
            return;
        }
    }
    const headers = { 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1 };
    if (range) headers['Content-Range'] = `bytes ${start}-${end}/${size}`;
    response.writeHead(range ? 206 : 200, headers);
    if (request.method === 'HEAD') response.end();
    else fs.createReadStream(file, { start, end }).pipe(response);
}

const plain = http.createServer(serve);
const secure = https.createServer({
    key: fs.readFileSync(path.join(work, 'server.key')),
    cert: fs.readFileSync(path.join(work, 'server.pem')),
}, serve);
plain.listen(8080, '0.0.0.0');
secure.listen(8443, '0.0.0.0');
let ready = 0;
for (const server of [plain, secure]) {
    server.on('error', error => { console.error(error); process.exit(1); });
    server.on('listening', () => {
        if (++ready === 2) fs.writeFileSync(path.join(work, 'ready'), 'ready\n');
    });
}
process.on('SIGTERM', () => {
    for (const server of [plain, secure]) {
        server.closeAllConnections();
        server.close();
    }
});