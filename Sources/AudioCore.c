#include "AudioCore.h"
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define SAMPLES KT_SAMPLE_COUNT
#define VOICES 64
#define CAPACITY 256
typedef struct { float *pcm; uint32_t length; } Sample;
typedef struct { int sample; uint32_t position; float gain; bool preview; } Voice;
typedef struct { int sample; float gain; uint64_t time; uint32_t epoch; } Hit;
typedef struct { Hit hits[CAPACITY]; _Atomic uint32_t read, write; } Queue;
struct KTEngine {
    AudioUnit unit;
    Sample samples[SAMPLES]; Voice voices[VOICES];
    Queue queues[2]; // SPSC: event-tap thread and main-thread previews each own a queue.
    _Atomic int profile; _Atomic float volume;
    _Atomic bool natural, enabled, keyVariation;
    _Atomic uint32_t epoch;
    _Atomic uint64_t count, inputCount, dropped, latencyNanos;
    uint32_t random[2], lastVariant[2], nextVoice, renderedEpoch;
    double nanosPerTick;
    bool running;
    AudioDeviceID tunedDevice;
    UInt32 previousBuffer, requestedBuffer;
    UInt32 bufferTarget;
};
static AudioDeviceID defaultDevice(void);
static void restoreBuffer(KTEngine *e) {
    if(!e->tunedDevice)return;
    UInt32 now=0,size=sizeof(now);
    AudioObjectPropertyAddress a={kAudioDevicePropertyBufferFrameSize,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    // Respect another audio application's subsequent buffer-size change.
    if(AudioObjectGetPropertyData(e->tunedDevice,&a,0,NULL,&size,&now)==noErr && now==e->requestedBuffer)
        AudioObjectSetPropertyData(e->tunedDevice,&a,0,NULL,sizeof(e->previousBuffer),&e->previousBuffer);
    e->tunedDevice=0;
}
void kt_refresh_device(KTEngine *e) {
    if(!e->unit)return;
    AudioDeviceID d=defaultDevice();if(!d || d==e->tunedDevice)return;
    restoreBuffer(e);
    UInt32 old=0,size=sizeof(old);Boolean settable=false;
    AudioObjectPropertyAddress a={kAudioDevicePropertyBufferFrameSize,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    if(AudioObjectGetPropertyData(d,&a,0,NULL,&size,&old)!=noErr || old<=e->bufferTarget)return;
    if(AudioObjectIsPropertySettable(d,&a,&settable)!=noErr || !settable)return;
    AudioValueRange range={0};size=sizeof(range);
    AudioObjectPropertyAddress r={kAudioDevicePropertyBufferFrameSizeRange,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    if(AudioObjectGetPropertyData(d,&r,0,NULL,&size,&range)!=noErr)return;
    UInt32 desired=(UInt32)fmax(e->bufferTarget,range.mMinimum);if(desired>=old || desired>range.mMaximum)return;
    if(AudioObjectSetPropertyData(d,&a,0,NULL,sizeof(desired),&desired)==noErr) {
        e->tunedDevice=d;e->previousBuffer=old;e->requestedBuffer=desired;
    }
}
KTEngine *kt_create(void) {
    KTEngine *e=calloc(1,sizeof(*e)); if(!e) return NULL;
    mach_timebase_info_data_t info; mach_timebase_info(&info);
    e->nanosPerTick=(double)info.numer/info.denom;
    e->random[0]=93271; e->random[1]=57379;
    e->lastVariant[0]=e->lastVariant[1]=UINT32_MAX;
    e->bufferTarget=64;
    atomic_store(&e->keyVariation,true);
    for(int i=0;i<VOICES;i++) e->voices[i].sample=-1;
    atomic_store(&e->volume,0.5f); return e;
}
bool kt_load(KTEngine *e,int index,const float *pcm,uint32_t frames) {
    if(!e || e->running || index<0 || index>=SAMPLES || !pcm || !frames) return false;
    float *copy=malloc(frames*sizeof(float)); if(!copy) return false;
    memcpy(copy,pcm,frames*sizeof(float)); free(e->samples[index].pcm);
    e->samples[index]=(Sample){copy,frames}; return true;
}
void kt_configure(KTEngine *e,int profile,float volume,bool natural,bool enabled) {
    atomic_store(&e->profile,profile<0?0:(profile>9?9:profile));
    atomic_store(&e->volume,fmaxf(0,fminf(1,volume)));
    atomic_store(&e->natural,natural);
    bool old=atomic_exchange(&e->enabled,enabled);
    if(old && !enabled) atomic_fetch_add(&e->epoch,1);
}
void kt_set_buffer_target(KTEngine *e,uint32_t frames) {
    if(!e->unit && (frames==64 || frames==128))e->bufferTarget=frames;
}
void kt_set_key_variation(KTEngine *e,bool enabled){atomic_store(&e->keyVariation,enabled);}
int kt_key_group(uint16_t keycode) {
    switch(keycode){
        case 48:return 1; // Tab
        case 57:return 2; // Caps Lock
        case 56:return 3; // left Shift
        case 60:return 4; // right Shift
        case 51:return 5; // Backspace
        case 36:case 76:return 6; // Return / keypad Enter
        case 49:return 7; // Space
        default:return 0;
    }
}
void kt_trigger(KTEngine *e,bool preview,uint16_t keycode,uint64_t time) {
    if(!preview && !atomic_load_explicit(&e->enabled,memory_order_relaxed)) return;
    int qid=preview?1:0; Queue *q=&e->queues[qid];
    uint32_t w=atomic_load_explicit(&q->write,memory_order_relaxed);
    uint32_t r=atomic_load_explicit(&q->read,memory_order_acquire);
    if(w-r>=CAPACITY){atomic_fetch_add(&e->dropped,1);return;}
    uint32_t rng=e->random[qid]; rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; e->random[qid]=rng;
    bool natural=atomic_load(&e->natural);
    int group=atomic_load(&e->keyVariation)?kt_key_group(keycode):0;
    uint32_t variant=0;
    if(natural && group==0){
        variant=rng%4;
        if(variant==e->lastVariant[qid])variant=(variant+1+((rng>>4)%3))%4;
        e->lastVariant[qid]=variant;
    }
    int sample=atomic_load(&e->profile)*KT_SAMPLES_PER_PROFILE+(group?3+group:variant);
    float gain=atomic_load(&e->volume)*(natural?(0.98f+((rng>>8)%41)/1000.f):1.f);
    q->hits[w%CAPACITY]=(Hit){sample,gain,time,atomic_load(&e->epoch)};
    atomic_store_explicit(&q->write,w+1,memory_order_release);
}
void kt_render(KTEngine *e,float *out,uint32_t frames,uint64_t outputTime) {
    memset(out,0,frames*2*sizeof(float));
    uint32_t epoch=atomic_load(&e->epoch);
    if(epoch!=e->renderedEpoch){
        for(int i=0;i<VOICES;i++) if(!e->voices[i].preview)e->voices[i].sample=-1;
        e->renderedEpoch=epoch;
    }
    for(int qid=0;qid<2;qid++) {
        Queue *q=&e->queues[qid]; uint32_t r=atomic_load_explicit(&q->read,memory_order_relaxed);
        uint32_t w=atomic_load_explicit(&q->write,memory_order_acquire);
        while(r!=w){
            Hit h=q->hits[r++%CAPACITY];
            if(!qid && (h.epoch!=epoch || !atomic_load(&e->enabled)))continue;
            if(!e->samples[h.sample].pcm)continue;
            int slot=-1;
            for(int j=0;j<VOICES;j++){int i=(e->nextVoice+j)%VOICES;if(e->voices[i].sample<0){slot=i;break;}}
            if(slot<0){slot=e->nextVoice;atomic_fetch_add(&e->dropped,1);}
            e->nextVoice=(slot+1)%VOICES;
            e->voices[slot]=(Voice){h.sample,0,h.gain,qid==1};
            atomic_fetch_add(&e->count,1);
            if(qid==0)atomic_fetch_add(&e->inputCount,1);
            if(h.time && outputTime>=h.time) atomic_store(&e->latencyNanos,(uint64_t)((outputTime-h.time)*e->nanosPerTick));
        }
        atomic_store_explicit(&q->read,r,memory_order_release);
    }
    bool active=false;
    for(int v=0;v<VOICES;v++) {
        Voice *voice=&e->voices[v]; if(voice->sample<0)continue;
        active=true; Sample *s=&e->samples[voice->sample];
        uint32_t n=s->length-voice->position;if(n>frames)n=frames;
        for(uint32_t i=0;i<n;i++){float a=s->pcm[voice->position+i]*voice->gain;out[i*2]+=a;out[i*2+1]+=a;}
        voice->position+=n;if(voice->position>=s->length)voice->sample=-1;
    }
    if(active) for(uint32_t i=0;i<frames*2;i++) {
        // Unity below 0.8; smooth bounded saturation only for dense chords.
        float x=out[i],a=fabsf(x);if(a>0.8f)out[i]=copysignf(0.8f+0.2f*(1.f-expf(-(a-0.8f)/0.2f)),x);
    }
}
static OSStatus callback(void *ctx,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *ts,UInt32 bus,UInt32 frames,AudioBufferList *data) {
    if(data && data->mNumberBuffers && data->mBuffers[0].mData)
        kt_render(ctx,data->mBuffers[0].mData,frames,(ts->mFlags&kAudioTimeStampHostTimeValid)?ts->mHostTime:mach_absolute_time());
    return noErr;
}
int32_t kt_start(KTEngine *e) {
    if(e->running)return 0;
    AudioComponentDescription desc={kAudioUnitType_Output,kAudioUnitSubType_DefaultOutput,kAudioUnitManufacturer_Apple,0,0};
    AudioComponent component=AudioComponentFindNext(NULL,&desc);if(!component)return -1;
    OSStatus status=AudioComponentInstanceNew(component,&e->unit);if(status)return status;
    AudioStreamBasicDescription format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
    status=AudioUnitSetProperty(e->unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,sizeof(format));
    if(status)goto fail;
    AURenderCallbackStruct cb={callback,e};
    status=AudioUnitSetProperty(e->unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&cb,sizeof(cb));
    if(status)goto fail;
    status=AudioUnitInitialize(e->unit);if(status)goto fail;
    kt_refresh_device(e);
    status=AudioOutputUnitStart(e->unit);if(status)goto fail;
    e->running=true;return 0;
fail:
    restoreBuffer(e);
    AudioComponentInstanceDispose(e->unit);e->unit=NULL;return status;
}
void kt_stop(KTEngine *e) {
    if(e->unit){AudioOutputUnitStop(e->unit);AudioUnitUninitialize(e->unit);AudioComponentInstanceDispose(e->unit);e->unit=NULL;}
    e->running=false;
    restoreBuffer(e);
    for(int i=0;i<VOICES;i++)e->voices[i].sample=-1;
    // Producer threads must be stopped before this function.
    for(int q=0;q<2;q++)atomic_store(&e->queues[q].read,atomic_load(&e->queues[q].write));
}
void kt_destroy(KTEngine *e){if(!e)return;kt_stop(e);for(int i=0;i<SAMPLES;i++)free(e->samples[i].pcm);free(e);}
uint64_t kt_count(KTEngine *e){return atomic_load(&e->count);}
uint64_t kt_input_count(KTEngine *e){return atomic_load(&e->inputCount);}
uint64_t kt_dropped(KTEngine *e){return atomic_load(&e->dropped);}
double kt_latency_ms(KTEngine *e){return atomic_load(&e->latencyNanos)/1e6;}
static AudioDeviceID defaultDevice(void){AudioDeviceID d=0;UInt32 size=sizeof(d);AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&size,&d);return d;}
uint32_t kt_buffer_frames(KTEngine *e){UInt32 n=0,size=sizeof(n);AudioObjectPropertyAddress a={kAudioDevicePropertyBufferFrameSize,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};AudioObjectGetPropertyData(defaultDevice(),&a,0,NULL,&size,&n);return n;}
double kt_device_rate(KTEngine *e){Float64 n=0;UInt32 size=sizeof(n);AudioObjectPropertyAddress a={kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};AudioObjectGetPropertyData(defaultDevice(),&a,0,NULL,&size,&n);return n;}
double kt_device_latency_ms(KTEngine *e){UInt32 n=0,safety=0,size=sizeof(n);AudioObjectPropertyAddress a={kAudioDevicePropertyLatency,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};AudioDeviceID d=defaultDevice();AudioObjectGetPropertyData(d,&a,0,NULL,&size,&n);a.mSelector=kAudioDevicePropertySafetyOffset;size=sizeof(safety);AudioObjectGetPropertyData(d,&a,0,NULL,&size,&safety);double sr=kt_device_rate(e);return sr>0?(n+safety)*1000.0/sr:0;}
