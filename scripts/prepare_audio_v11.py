#!/usr/bin/env python3
"""Build real, named-key samples from pinned Mechvibes recordings; never synthesize key sizes.
Dependencies for this offline authoring script: numpy, scipy, soundfile.
"""
import os,json,pathlib,hashlib,math
import numpy as np
import soundfile as sf
from scipy import signal
from scipy.io import wavfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
WORK=pathlib.Path(os.environ.get('KEYTONE_AUDIO_WORK',ROOT/'.build/audio-sources'))
OUT=ROOT/'Resources/Sounds'
META=[
('eg-crystal-purple','水晶紫轴','推荐 · 圆润、干净','Everglide Crystal Purple。采用同套逐键录音，保留触底主体；去除空白、次声与多余底噪。'),
('topre-purple-hybrid-pbt','Topre 紫轴','静电容 · 柔和、有空腔感','Topre Purple Hybrid / PBT 键帽。采用实际按下声，避免把更响的松开回弹误当成敲击。'),
('eg-oreo','奥利奥轴','段落 · 厚实、低频共鸣','Everglide Oreo。保留录音中饱满的箱体共鸣，大键来自各自的原始录音。'),
('cherrymx-black-pbt','Cherry 黑轴 / PBT','线性 · 扎实、短促','Cherry MX Black，PBT 键帽版本。真实逐键采样；空格和左右 Shift 使用独立按键片段。'),
('cherrymx-red-abs','Cherry 红轴 / ABS','线性 · 轻快、清楚','Cherry MX Red，ABS 键帽版本。轻快触底声，保留同一套录音中大键的自然差别。'),
('cherrymx-brown-pbt','Cherry 茶轴 / PBT','段落 · 清爽、克制','Cherry MX Brown，PBT 键帽版本。没有青轴的独立点击机构，重点保留触底音。'),
('cherrymx-black-abs','Cherry 黑轴 / ABS','线性 · 明亮共鸣','Cherry MX Black，ABS 键帽录音版本。与 PBT 版本是不同实录，差异不只由键帽材料决定。'),
('cherrymx-brown-abs','Cherry 茶轴 / ABS','段落 · 轻巧、偏亮','Cherry MX Brown，ABS 键帽录音版本。适合喜欢轻巧、清楚触底声的偏好。'),
('cherrymx-blue-pbt','Cherry 青轴 / PBT','有声段落 · 清脆点击','Cherry MX Blue，PBT 键帽版本。保留真实点击和触底的先后结构，声音本身比较明亮。'),
('cherrymx-blue-abs','Cherry 青轴 / ABS','有声段落 · 明亮机械音','Cherry MX Blue，ABS 键帽版本。保留点击机构的特征，适合喜欢明显咔嗒声的偏好。')]
# Slot identity is shared with AudioCore.h. Slots 0-3 are four ordinary physical keys.
KEYS=['KeyF','KeyJ','KeyD','KeyK','Tab','CapsLock','ShiftLeft','ShiftRight','Backspace','Enter','Space']
RATE=48000
OUT.mkdir(parents=True,exist_ok=True)
profiles=[];audit=[];manifest=[]
for name,title,subtitle,detail in META:
    folder=WORK/name;c=json.loads((folder/'config.json').read_text());audio=folder/c['audio_file']
    raw,sr=sf.read(audio,always_2d=True);mono=raw.mean(axis=1)
    # Remove DC/subsonic handling noise and lightly soften the upper treble.
    mono=signal.sosfilt(signal.butter(2,65,btype='highpass',fs=sr,output='sos'),mono)
    low=signal.sosfilt(signal.butter(1,4200,btype='lowpass',fs=sr,output='sos'),mono)
    mono=.72*mono+.28*low  # <= 2.85 dB at the highest frequencies, not pitch shifting.
    clips=[];rows=[]
    for slot,key in enumerate(KEYS):
        intervals=c['definitions'][key]['timing'];start,end=intervals[0]
        # Verified against waveform clusters: first interval covers press, second is release.
        a=int(round(start*sr/1000));b=int(round(end*sr/1000));x=mono[a:b].copy()
        assert len(x)>400,(name,key,'missing press')
        envelope=np.sqrt(signal.convolve(x*x,np.ones(max(3,int(sr*.0003)))/max(3,int(sr*.0003)),mode='same'))
        peak=abs(x).max();env_peak=envelope.max()
        active=np.flatnonzero(envelope>env_peak*.30)
        assert len(active)>0
        onset=max(0,int(active[0])-int(sr*.00025))
        # Keep the full press decay until it is below -42 dB of the transient.
        tail_active=np.flatnonzero(envelope>env_peak*.008)
        finish=min(len(x),max(int(tail_active[-1])+int(sr*.006),onset+int(sr*.035)))
        y=x[onset:finish]
        # A soft gate attenuates only the final low-level floor; never alters the main impact.
        if len(y)>int(sr*.025):
            gate_start=max(int(np.argmax(abs(y)))+int(sr*.014),len(y)-int(sr*.018))
            gate_start=min(gate_start,len(y)-1)
            y[gate_start:]*=np.linspace(1,0,len(y)-gate_start)**1.2
        y[:min(8,len(y))]*=np.linspace(0,1,min(8,len(y)))
        y[-1]=0
        if sr!=RATE:
            divisor=math.gcd(sr,RATE);y=signal.resample_poly(y,RATE//divisor,sr//divisor)
        y[0]=y[-1]=0
        clips.append(y)
        rows.append(dict(profile=name,slot=slot,key=key,source_start_ms=start,source_press_end_ms=end,trim_start_ms=onset/sr*1000,source_audio_sha256=hashlib.sha256(audio.read_bytes()).hexdigest(),source_config_sha256=hashlib.sha256((folder/'config.json').read_bytes()).hexdigest()))
    # One gain per board retains measured relative loudness between ordinary and wide keys.
    ordinary_level=np.median([np.sqrt(np.mean(x[:min(len(x),1440)]**2)) for x in clips[:4]])
    gain=min(.075/max(ordinary_level,1e-8),.72/max(np.max(abs(x)) for x in clips))
    for slot,(y,row) in enumerate(zip(clips,rows)):
        y=y*gain;path=OUT/f'{name}-{slot}.wav';pcm=np.round(y*32767).astype('<i2');wavfile.write(path,RATE,pcm)
        row.update(duration_ms=len(y)/48,peak=float(max(abs(y))),rms=float(np.sqrt(np.mean(y*y))),gain=gain,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        audit.append(row)
    wave=np.array([max(abs(chunk)) for chunk in np.array_split(clips[0],40)]);wave=(wave/max(wave))**.55
    source=f'https://github.com/hainguyents13/mechvibes/tree/16afce45bd7cf12be399e2d1a8d20f221067f534/soundpacks/keyboard/{name}'
    profiles.append(dict(id=name,name=title,subtitle=subtitle,detail=detail,author='Mechvibes · MIT',url=source,waveform=wave.tolist()))
    manifest.append(dict(id=name,upstream_commit='16afce45bd7cf12be399e2d1a8d20f221067f534',source=source,license='MIT',audio_file=c['audio_file'],source_sample_rate=sr,source_channels=raw.shape[1],keys=KEYS))
# Only after all packs validate, retire old assets from the build input. Git retains v1.0.
expected={f"{p['id']}-{i}.wav" for p in profiles for i in range(len(KEYS))}
for p in OUT.glob('*.wav'):
    if p.name not in expected:p.unlink()
(ROOT/'Resources/profiles.json').write_text(json.dumps(profiles,ensure_ascii=False,indent=2))
(ROOT/'Resources/sample-audit.json').write_text(json.dumps(audit,indent=2))
(ROOT/'Resources/sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print('Prepared',len(audit),'named-key clips; PCM bytes:',sum(p.stat().st_size for p in OUT.glob('*.wav')))
for p in profiles:
 a=[r for r in audit if r['profile']==p['id']]
 print(p['name'],': durations',round(min(r['duration_ms'] for r in a)),round(max(r['duration_ms'] for r in a)),'ms; max peak',round(max(r['peak'] for r in a),3))
