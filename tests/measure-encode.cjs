const fs = require('node:fs');
const { spawn, execFileSync } = require('node:child_process');
const clockTicks = Number(execFileSync('getconf', ['CLK_TCK'], { encoding: 'utf8' }).trim());

async function measure(binary, frame, tune, geometry, frameRate) {
    const started = process.hrtime.bigint();
    const child = spawn(binary, ['-nostdin', '-v', 'error',
        '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-video_size', geometry,
        '-framerate', String(frameRate), '-stream_loop', '-1', '-i', frame,
        '-f', 's16le', '-ar', '44100', '-ac', '2', '-i', 'pipe:0',
        '-map', '0:v:0', '-map', '1:a:0', '-t', '5',
        '-c:v', 'libx264', '-preset', 'veryfast', '-tune', tune,
        '-threads:v', '2', '-g', String(frameRate * 2), '-keyint_min', String(frameRate * 2), '-sc_threshold', '0',
        '-b:v', '500k', '-maxrate', '500k', '-bufsize', '1000k',
        '-c:a', 'aac', '-ar', '48000', '-b:a', '128k',
        '-f', 'flv', '-flush_packets', '1', 'pipe:1'], { stdio: ['pipe', 'pipe', 'inherit'] });
    let buffer = Buffer.alloc(0);
    let header = false;
    let firstVideoMs;
    let firstAudioMs;
    let total = 0;
    let ticks = 0;
    const elapsed = () => Number(process.hrtime.bigint() - started) / 1e6;
    const samples = [];
    const resourceTimer = setInterval(() => {
        try {
            const status = fs.readFileSync(`/proc/${child.pid}/status`, 'utf8');
            const processStat = fs.readFileSync(`/proc/${child.pid}/stat`, 'utf8');
            const counters = processStat.slice(processStat.lastIndexOf(')') + 2).trim().split(/\s+/);
            samples.push({
                elapsed: elapsed(), cpuTicks: Number(counters[11]) + Number(counters[12]),
                rss: Number(/^VmRSS:\s+(\d+) kB$/m.exec(status)?.[1] || 0),
                threads: Number(/^Threads:\s+(\d+)$/m.exec(status)?.[1] || 0),
                descriptors: fs.readdirSync(`/proc/${child.pid}/fd`).length
            });
        } catch (error) {
            if (error.code !== 'ENOENT' && error.code !== 'ESRCH') console.error(error);
        }
    }, 100);
    child.stdout.on('data', chunk => {
        total += chunk.length;
        buffer = Buffer.concat([buffer, chunk]);
        if (!header && buffer.length >= 13) {
            if (buffer.subarray(0, 3).toString() !== 'FLV') throw new Error('Invalid FLV');
            buffer = buffer.subarray(buffer.readUInt32BE(5) + 4);
            header = true;
        }
        while (header && buffer.length >= 11) {
            const length = buffer.readUIntBE(1, 3);
            if (buffer.length < length + 15) break;
            const type = buffer[0];
            if (type === 9 && length >= 2 && buffer[12] === 1 && firstVideoMs === undefined) firstVideoMs = elapsed();
            if (type === 8 && length >= 2 && buffer[12] === 1 && firstAudioMs === undefined) firstAudioMs = elapsed();
            buffer = buffer.subarray(length + 15);
        }
    });
    child.stdin.on('error', error => { if (error.code !== 'EPIPE') console.error(error); });
    const chunk = Buffer.alloc(3528);
    const timer = setInterval(() => {
        if (child.stdin.destroyed) return;
        if (ticks++ >= 250) {
            clearInterval(timer);
            child.stdin.end();
        } else if (!child.stdin.writableNeedDrain) child.stdin.write(chunk);
    }, 20);
    const deadline = setTimeout(() => child.kill('SIGKILL'), 15000);
    await new Promise((resolve, reject) => {
        child.on('error', reject);
        child.on('close', code => code === 0 ? resolve() : reject(new Error(`Encoder exit ${code}`)));
    }).finally(() => { clearInterval(timer); clearInterval(resourceTimer); clearTimeout(deadline); });
    if (firstVideoMs === undefined || firstAudioMs === undefined) throw new Error('Missing encoded A/V tags');
    if (samples.length < 2) throw new Error('Insufficient encode resource samples');
    const initial = samples[0];
    const final = samples.at(-1);
    console.log(JSON.stringify({
        tune, geometry, frameRate,
        firstVideoMs: Math.round(firstVideoMs), firstAudioMs: Math.round(firstAudioMs), totalBytes: total,
        cpuPercent: Number(((final.cpuTicks - initial.cpuTicks) / clockTicks /
            (final.elapsed - initial.elapsed) * 100000).toFixed(2)),
        peakRssKiB: Math.max(...samples.map(sample => sample.rss)),
        initialDescriptors: initial.descriptors, finalDescriptors: final.descriptors,
        initialThreads: initial.threads, finalThreads: final.threads
    }));
    return firstVideoMs;
}

(async () => {
    const [binary, frame, geometry = '320x180', rate = '10'] = process.argv.slice(2);
    if (!binary || !frame) throw new Error('binary and frame required');
    const dimensions = /^(\d+)x(\d+)$/.exec(geometry);
    const frameRate = Number(rate);
    if (!dimensions || dimensions.slice(1).some(value => Number(value) < 2 || Number(value) % 2) ||
        !Number.isSafeInteger(frameRate) || frameRate < 1) throw new Error('Even geometry dimensions and a positive integer frame rate required');
    await measure(binary, frame, 'stillimage', geometry, frameRate);
    const lowLatency = await measure(binary, frame, 'stillimage,zerolatency', geometry, frameRate);
    if (lowLatency > 1000) throw new Error(`First video exceeds one second: ${lowLatency} ms`);
})().catch(error => { console.error(error); process.exitCode = 1; });