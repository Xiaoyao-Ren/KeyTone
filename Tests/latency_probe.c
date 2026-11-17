#include "../Sources/AudioCore.h"
#include <mach/mach_time.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
static int cmp(const void *a,const void *b){double d=*(double*)a-*(double*)b;return (d>0)-(d<0);}
int main(int argc,char **argv){KTEngine *e=kt_create();kt_set_buffer_target(e,argc>1?atoi(argv[1]):64);float sample[480]={0};for(int i=0;i<KT_SAMPLE_COUNT;i++)kt_load(e,i,sample,480);kt_configure(e,0,0,0,1);int s=kt_start(e);if(s){printf("start error=%d\n",s);return 1;}double results[100];usleep(100000);for(int i=0;i<100;i++){kt_trigger(e,0,0,mach_absolute_time());usleep(40000+i*13);results[i]=kt_latency_ms(e);}qsort(results,100,sizeof(double),cmp);printf("buffer_frames=%u rate=%.0f reported_device_latency_ms=%.3f\n",kt_buffer_frames(e),kt_device_rate(e),kt_device_latency_ms(e));printf("callback_to_output_timestamp_ms min=%.3f median=%.3f p95=%.3f max=%.3f rendered=%llu dropped=%llu\n",results[0],results[50],results[95],results[99],kt_count(e),kt_dropped(e));kt_destroy(e);}
