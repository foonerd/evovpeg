const fs = require('node:fs');
const { spawn, execFileSync } = require('node:child_process');
const clockTicks = Number(execFileSync('getconf', ['CLK_TCK'], { encoding: 'utf8' }).trim());

async function measure(label, binary, clip, durationSeconds) {
    const started = process.hrtime.bigint();
    const child = spawn(binary, ['-nostdin', '-v', 'error', '-filter_threads', '1', '-threads', '1', '-re',
        '-stream_loop', '-1', '-i', clip, '-t', String(durationSeconds), '-an', '-sn',
        '-threads:v', '1', '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-'], { stdio: ['ignore', 'ignore', 'inherit'] });
    const samples = [];
    const timer = setInterval(() => {
        try {
            const text = fs.readFileSync(`/proc/${child.pid}/smaps_rollup`, 'utf8');
            const fields = Object.fromEntries([...text.matchAll(/^(\w+):\s+(\d+) kB$/gm)]
                .map(match => [match[1], Number(match[2])]));
            const elapsed = Number(process.hrtime.bigint() - started) / 1e9;
            const mappings = fs.readFileSync(`/proc/${child.pid}/smaps`, 'utf8').split(/\n(?=[0-9a-f]+-[0-9a-f]+ )/);
            const executable = fs.readlinkSync(`/proc/${child.pid}/exe`);
            let heap = 0;
            let stack = 0;
            let executableRss = 0;
            for (const mapping of mappings) {
                const anonymous = Number(/^Anonymous:\s+(\d+) kB$/m.exec(mapping)?.[1] || 0);
                const header = mapping.split('\n', 1)[0];
                if (header.endsWith('[heap]')) heap += anonymous;
                if (header.endsWith('[stack]')) stack += anonymous;
                if (header.endsWith(` ${executable}`)) {
                    executableRss += Number(/^Rss:\s+(\d+) kB$/m.exec(mapping)?.[1] || 0);
                }
            }
            const descriptors = fs.readdirSync(`/proc/${child.pid}/fd`).length;
            const threads = fs.readdirSync(`/proc/${child.pid}/task`).length;
            const processStat = fs.readFileSync(`/proc/${child.pid}/stat`, 'utf8');
            const counters = processStat.slice(processStat.lastIndexOf(')') + 2).trim().split(/\s+/);
            const cpuTicks = Number(counters[11]) + Number(counters[12]);
            if (elapsed >= 3) samples.push({ elapsed, cpuTicks, rss: fields.Rss, anon: fields.Anonymous, executableRss, heap, stack, descriptors, threads });
        } catch (error) {
            if (error.code !== 'ENOENT' && error.code !== 'ESRCH') console.error(error);
        }
    }, 100);
    await new Promise((resolve, reject) => {
        child.on('error', reject);
        child.on('close', code => code === 0 ? resolve() : reject(new Error(`${label} exit ${code}`)));
    }).finally(() => clearInterval(timer));
    if (samples.length < 10) throw new Error('Insufficient memory samples');
    const initial = samples.slice(0, 10);
    const final = samples.slice(-10);
    const mean = (values, field) => Math.round(values.reduce((sum, value) => sum + value[field], 0) / values.length);
    const intervals = new Map();
    for (const sample of samples) {
        const interval = Math.floor(sample.elapsed / 30);
        if (!intervals.has(interval)) intervals.set(interval, []);
        intervals.get(interval).push(sample);
    }
    console.log(JSON.stringify({
        label, samples: samples.length,
        cpuPercent: Number(((samples.at(-1).cpuTicks - samples[0].cpuTicks) / clockTicks /
            (samples.at(-1).elapsed - samples[0].elapsed) * 100).toFixed(2)),
        initialRssKiB: mean(initial, 'rss'), finalRssKiB: mean(final, 'rss'),
        initialAnonKiB: mean(initial, 'anon'), finalAnonKiB: mean(final, 'anon'),
        peakRssKiB: Math.max(...samples.map(sample => sample.rss)),
        peakAnonKiB: Math.max(...samples.map(sample => sample.anon)),
        initialExecutableRssKiB: mean(initial, 'executableRss'), finalExecutableRssKiB: mean(final, 'executableRss'),
        initialHeapKiB: mean(initial, 'heap'), finalHeapKiB: mean(final, 'heap'),
        initialStackKiB: mean(initial, 'stack'), finalStackKiB: mean(final, 'stack'),
        initialDescriptors: mean(initial, 'descriptors'), finalDescriptors: mean(final, 'descriptors'),
        initialThreads: mean(initial, 'threads'), finalThreads: mean(final, 'threads'),
        intervals: Array.from(intervals, ([interval, values]) => ({
            fromSeconds: interval * 30, samples: values.length,
            meanRssKiB: mean(values, 'rss'), minRssKiB: Math.min(...values.map(sample => sample.rss)),
            peakRssKiB: Math.max(...values.map(sample => sample.rss)),
            meanAnonKiB: mean(values, 'anon'), minAnonKiB: Math.min(...values.map(sample => sample.anon)),
            peakAnonKiB: Math.max(...values.map(sample => sample.anon))
        }))
    }));
}

(async () => {
    const [baseline, candidate, clip, duration = '20'] = process.argv.slice(2);
    if (!baseline || !candidate || !clip) throw new Error('baseline, candidate and clip required');
    const durationSeconds = Number(duration);
    if (!Number.isSafeInteger(durationSeconds) || durationSeconds < 5) {
        throw new Error('duration must be an integer of at least 5 seconds');
    }
    await measure('baseline', baseline, clip, durationSeconds);
    await measure('candidate', candidate, clip, durationSeconds);
})().catch(error => { console.error(error); process.exitCode = 1; });