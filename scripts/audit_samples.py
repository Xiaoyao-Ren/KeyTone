#!/usr/bin/env python3
import array,hashlib,json,math,pathlib,sys,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
profiles=json.loads((ROOT/'Resources/profiles.json').read_text());audit=json.loads((ROOT/'Resources/sample-audit.json').read_text())
assert len(profiles)==10 and len({p['id'] for p in profiles})==10
assert len(audit)==110
keys=['KeyF','KeyJ','KeyD','KeyK','Tab','CapsLock','ShiftLeft','ShiftRight','Backspace','Enter','Space']
seen=set();durations=[];onsets=[];peaks=[]
for p in profiles:
    source=json.loads((ROOT/'AudioSources'/p['id']/'config.json').read_text())
    gain=[]
    for i,key in enumerate(keys):
        path=ROOT/'Resources/Sounds'/f"{p['id']}-{i}.wav"
        row=next(a for a in audit if a['profile']==p['id'] and a['slot']==i)
        assert row['key']==key and [row['source_start_ms'],row['source_press_end_ms']]==source['definitions'][key]['timing'][0]
        assert hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256']
        gain.append(row['gain'])
        with wave.open(str(path)) as f:
            assert (f.getnchannels(),f.getsampwidth(),f.getframerate())==(1,2,48000)
            data=f.readframes(f.getnframes())
        digest=hashlib.sha256(data).hexdigest();assert digest not in seen,(path,'duplicate');seen.add(digest)
        samples=array.array('h',data)
        if sys.byteorder!='little':samples.byteswap()
        peak=max(abs(x) for x in samples);rms=math.sqrt(sum(x*x for x in samples)/len(samples))
        assert 500<peak<25000,(path,peak)
        assert samples[0]==samples[-1]==0,path
        assert .025<len(samples)/48000<.2,path
        assert rms>80,(path,rms)
        assert abs(sum(samples)/len(samples))<32768*.025,path
        onset=next(k for k,v in enumerate(samples) if abs(v)>=peak*.05)/48
        assert onset<2,(path,onset)
        durations.append(len(samples)/48);onsets.append(onset);peaks.append(peak/32768)
    assert max(gain)==min(gain),'Wide-key relative dynamics must not be independently normalized'
print(f'PASS: {len(seen)} unique clips; all 70 wide-key clips match exact upstream key labels/timings; same gain per board; PCM16/48 kHz; zero endpoints; onset <= {max(onsets):.3f} ms; duration {min(durations):.1f}–{max(durations):.1f} ms; peak <= {max(peaks):.3f}.')
