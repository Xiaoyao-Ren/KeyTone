#include "../Sources/AudioCore.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
#include <mach/mach_time.h>
#include <unistd.h>

static float maxabs(float *a,int n){float peak=0;for(int i=0;i<n;i++){assert(isfinite(a[i]));peak=fmaxf(peak,fabsf(a[i]));}return peak;}
typedef struct {KTEngine *e;bool preview;_Atomic int *done;} Producer;
static void *produce(void *arg){Producer *p=arg;for(int i=0;i<4000;i++){kt_trigger(p->e,p->preview,0,mach_absolute_time());usleep(200);}atomic_fetch_add(p->done,1);return NULL;}
int main(void){
    KTEngine *e=kt_create();assert(e);float pcm[480],out[1024];
    for(int i=0;i<480;i++)pcm[i]=.1f*sinf(i*.2f);
    assert(!kt_load(e,-1,pcm,480));assert(!kt_load(e,KT_SAMPLE_COUNT,pcm,480));assert(!kt_load(e,0,pcm,0));
    for(int i=0;i<KT_SAMPLE_COUNT;i++)assert(kt_load(e,i,pcm,480));
    kt_configure(e,0,1,false,true);kt_trigger(e,false,0,0);kt_render(e,out,128,0);
    assert(kt_count(e)==1);assert(kt_input_count(e)==1);assert(maxabs(out,256)>.09f);
    for(int i=0;i<128;i++)assert(out[2*i]==out[2*i+1]);
    kt_render(e,out,512,0);kt_render(e,out,512,0);assert(maxabs(out,1024)==0);
    // Existing and queued live voices must be silenced on pause.
    kt_trigger(e,false,0,0);kt_render(e,out,128,0);kt_trigger(e,false,0,0);
    kt_configure(e,0,1,false,false);kt_render(e,out,512,0);assert(maxabs(out,1024)==0);
    kt_trigger(e,false,0,0);kt_render(e,out,128,0);assert(maxabs(out,256)==0);
    // Preview remains available while global monitoring is off.
    kt_trigger(e,true,0,0);kt_render(e,out,128,0);assert(maxabs(out,256)>.09f);assert(kt_input_count(e)==2);
    kt_stop(e);kt_configure(e,0,0,false,true);kt_trigger(e,false,0,0);kt_render(e,out,512,0);assert(maxabs(out,1024)==0);
    // A 64-note chord is finite and bounded, and no note is discarded.
    kt_stop(e);kt_configure(e,9,1,true,true);uint64_t before=kt_count(e);
    for(int i=0;i<64;i++)kt_trigger(e,false,0,0);kt_render(e,out,512,0);
    assert(kt_count(e)==before+64);assert(kt_dropped(e)==0);assert(maxabs(out,1024)<=1);
    // Each queue admits 256 entries, then reports overflow without corrupting memory.
    for(int i=0;i<300;i++)kt_trigger(e,false,0,0);assert(kt_dropped(e)==44);
    kt_stop(e);kt_destroy(e);
    e=kt_create();for(int i=0;i<KT_SAMPLE_COUNT;i++)assert(kt_load(e,i,pcm,480));kt_configure(e,4,.5,true,true);
    _Atomic int done=0;Producer a={e,false,&done},b={e,true,&done};pthread_t t1,t2;
    pthread_create(&t1,NULL,produce,&a);pthread_create(&t2,NULL,produce,&b);
    while(atomic_load(&done)<2){kt_render(e,out,512,mach_absolute_time());assert(maxabs(out,1024)<=1);usleep(100);}
    pthread_join(t1,NULL);pthread_join(t2,NULL);kt_render(e,out,512,mach_absolute_time());
    assert(kt_count(e)==8000);assert(kt_input_count(e)==4000);assert(kt_dropped(e)==0);
    printf("PASS: pause, preview, volume, stereo, 64 voices, overflow, 8000 concurrent triggers; zero dropped in stress test.\n");
    kt_destroy(e);
    // Validate the complete keycode -> slot -> rendered-sample path for every profile.
    e=kt_create();float marker[64];
    for(int slot=0;slot<KT_SAMPLE_COUNT;slot++){
        for(int i=0;i<64;i++)marker[i]=(slot+1)*.001f;
        assert(kt_load(e,slot,marker,64));
    }
    uint16_t keys[]={0,48,57,56,60,51,36,49,76};
    int offsets[]={0,4,5,6,7,8,9,10,9};
    for(int profile=0;profile<KT_PROFILE_COUNT;profile++){
        kt_configure(e,profile,1,false,true);
        for(int i=0;i<9;i++){
            kt_trigger(e,false,keys[i],0);kt_render(e,out,64,0);
            assert(fabsf(out[0]-(profile*KT_SAMPLES_PER_PROFILE+offsets[i]+1)*.001f)<1e-6f);
        }
        kt_set_key_variation(e,false);
        for(int i=0;i<9;i++){
            kt_trigger(e,false,keys[i],0);kt_render(e,out,64,0);
            assert(fabsf(out[0]-(profile*KT_SAMPLES_PER_PROFILE+1)*.001f)<1e-6f);
        }
        kt_set_key_variation(e,true);
    }
    assert(kt_key_group(117)==0);assert(kt_key_group(55)==0);assert(kt_key_group(53)==0);
    // Natural variation must never select the same ordinary recording consecutively.
    kt_configure(e,0,1,true,true);int previous=-1;
    for(int i=0;i<1000;i++){
        kt_trigger(e,false,0,0);kt_render(e,out,64,0);
        int selected=(int)lroundf(out[0]*1000)-1;
        assert(selected>=0 && selected<4 && selected!=previous);previous=selected;
    }
    printf("PASS: all 10 profiles route all wide keys correctly; disabling differences restores ordinary key; 1000 natural variations avoid consecutive duplicates.\n");
    kt_destroy(e);return 0;
}
