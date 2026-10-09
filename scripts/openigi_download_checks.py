#!/usr/bin/env python3
"""Run native Grabber/engine against the public OpenIGI OS links and stream independent curl hashes.
Artifacts are bounded to one OS download and removed by the native runner; JSON evidence remains.
"""
import argparse, concurrent.futures, datetime, hashlib, json, os, pathlib, re, shutil, subprocess, tempfile, time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--os', choices=['win-x64','linux-x64','osx-arm64'], action='append', dest='targets')
    parser.add_argument('--reuse-native', action='store_true', help='Verify existing native evidence without downloading it again')
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True, exist_ok=True)
    report = {'page': 'https://openigi.com/', 'dateUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'checks': []}
    for target in args.targets or ['win-x64', 'linux-x64', 'osx-arm64']:
        item = {'os': target, 'url': f'https://api.openigi.com/download/{target}'}
        owned_artifacts = None
        try:
            if shutil.disk_usage(args.output).free < 150 * 1024 * 1024:
                raise RuntimeError('Less than 150 MiB free for sequential download')
            native_path = args.output / f'{target}.native.json'
            if args.reuse_native and native_path.exists():
                item['nativeExit'] = 0
                item['reusedNativeEvidence'] = True
            else:
                owned_artifacts = pathlib.Path(tempfile.mkdtemp(prefix=f"native-{target}-",dir=args.output))
                environment = os.environ.copy()
                environment.update(IDM_OPENIGI_OS=target, IDM_OPENIGI_OUTPUT=str(native_path.resolve()),IDM_OPENIGI_WORK_DIRECTORY=str(owned_artifacts.resolve()))
                native = subprocess.run([str(root / '.build/debug/IDMCoreChecks')], env=environment, cwd=root,
                                        capture_output=True, text=True, timeout=args.timeout)
                item['nativeExit'] = native.returncode
                if native.returncode:
                    raise RuntimeError(native.stderr[-3000:] or native.stdout[-3000:])
            item['native'] = json.loads(native_path.read_text())
            headers_path = args.output / f'{target}.curl-headers.txt'
            started = time.monotonic()
            size = item['native']['bytes']
            chunk_bytes = 1024 * 1024
            ranges = [(start, min(size - 1, start + chunk_bytes - 1)) for start in range(0, size, chunk_bytes)]
            probe_headers = args.output / f'{target}.redirect-headers.txt'
            probe = subprocess.run(['curl','--http1.1','--fail','--silent','--show-error','--location','--max-time','90',
                                    '--proto','=https','--proto-redir','=https','--range','0-0','--max-filesize','1048576',
                                    '--dump-header',str(probe_headers),item['url']],capture_output=True,timeout=95)
            if probe.returncode or len(probe.stdout) != 1:
                raise RuntimeError('Reference redirect probe failed: '+probe.stderr.decode(errors='replace'))
            redirects = re.findall(r'^location:\s*(https://[^\r\n]+)',probe_headers.read_text(),re.I|re.M)
            reference_url = redirects[-1] if redirects else item['url']
            def fetch(bounds):
                start,end = bounds
                received = bytearray()
                transport_errors = []
                for attempt in range(8):
                    current = start + len(received)
                    command = ['curl','--http1.1','--fail','--silent','--show-error','--location','--max-time','60',
                               '--proto','=https','--proto-redir','=https','--max-filesize',str(chunk_bytes),
                               '--range',f'{current}-{end}',reference_url]
                    if current == 0:
                        command += ['--dump-header',str(headers_path)]
                    reference = subprocess.run(command,capture_output=True,timeout=65)
                    if reference.returncode not in (0,16,18,28,52,55,56):
                        raise RuntimeError(reference.stderr.decode(errors='replace'))
                    if reference.returncode:
                        transport_errors.append(reference.returncode)
                    received.extend(reference.stdout)
                    if len(received) == end-start+1:
                        return bytes(received),attempt+1,transport_errors
                    if len(received) > end-start+1:
                        raise RuntimeError('Unexpected curl range length')
                raise RuntimeError('Reference range did not finish after eight bounded attempts')
            digest = hashlib.sha256()
            count = 0
            request_attempts = 0
            transport_exit_codes = []
            # Keep only eight range responses in flight, consume in byte order.
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
                pending = {}
                next_submit = 0
                for index in range(len(ranges)):
                    while next_submit < min(len(ranges), index + 8):
                        pending[next_submit] = executor.submit(fetch, ranges[next_submit])
                        next_submit += 1
                    chunk,attempt_count,transport_errors = pending.pop(index).result()
                    transport_exit_codes.extend(transport_errors)
                    request_attempts += attempt_count
                    digest.update(chunk)
                    count += len(chunk)
            item['curl'] = {'exit': 0, 'bytes': count, 'sha256': digest.hexdigest(), 'seconds': time.monotonic() - started,
                            'method': 'independent curl HTTP/1.1 ordered one-MiB ranges', 'connections': 8, 'finalURL': reference_url, 'requestAttempts': request_attempts, 'ranges': len(ranges), 'transportExitCodes': transport_exit_codes}
            item['match'] = count == item['native']['bytes'] and digest.hexdigest() == item['native']['sha256']
            if not item['match']:
                raise RuntimeError('Native download differs from independent curl')
        except Exception as error:
            item['error'] = str(error)
        if owned_artifacts is not None and owned_artifacts.exists():
            shutil.rmtree(owned_artifacts)
        report['checks'].append(item)
        (args.output / 'openigi-downloads.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({'os': target, 'match': item.get('match', False), 'error': item.get('error') }), flush=True)
    report['passed'] = all(item.get('match', False) for item in report['checks'])
    (args.output / 'openigi-downloads.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
