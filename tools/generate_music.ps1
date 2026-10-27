# Offline original placeholder compositions, no third-party samples or runtime synthesis.
# Reproducible PCM16 mono 22050 Hz; 8 bars per loop.
$ErrorActionPreference='Stop'
$output=Join-Path $PSScriptRoot '../assets/audio'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.IO;
public static class DinerMusic {
 const int R=22050;
 static double[] buffer;
 static void Note(double at,double length,int midi,double gain,int voice) {
  double f=440*Math.Pow(2,(midi-69)/12.0);
  int start=(int)(at*R),count=(int)(length*R);
  for(int i=0;i<count;i++) {
   double t=(double)i/R, phase=2*Math.PI*f*t;
   double env=Math.Min(1,t/.012)*Math.Min(1,(length-t)/.06)*Math.Exp(-t*(voice==0?3:1));
   double wave=Math.Sin(phase)+.18*Math.Sin(phase*2)+.08*Math.Sin(phase*3);
   buffer[(start+i)%buffer.Length]+=wave*env*gain;
  }
 }
 static void Drum(double at,bool bass,double gain) {
  int start=(int)(at*R);uint noise=7831;
  for(int i=0;i<R/6;i++) {
   double t=(double)i/R;noise=1664525*noise+1013904223;
   double s=bass?Math.Sin(2*Math.PI*(55*t+25*.025*(1-Math.Exp(-t/.025)))):((noise>>8)/(double)0xffffff*2-1);
   buffer[(start+i)%buffer.Length]+=s*Math.Min(1,t/.004)*Math.Exp(-t*(bass?24:65))*gain;
  }
 }
 public static void Write(string path,int bpm,int mode) {
  double beat=60.0/bpm;buffer=new double[(int)Math.Round(32*beat*R)];
  int[] roots={48,45,53,43,48,45,53,43};
  int[][] melody={new[]{72,76,79,81,79,76,74,72},new[]{76,79,81,84,81,79,76,74},new[]{72,74,76,79,81,79,76,72}};
  for(int bar=0;bar<8;bar++) {
   int root=roots[bar];
   Note(bar*4*beat,3.8*beat,root,.09,1);
   Note(bar*4*beat,3.8*beat,root+12,.035,1);Note(bar*4*beat,3.8*beat,root+19,.03,1);
   for(int j=0;j<4;j++) {
    int step=bar*4+j;
    Note((step+(mode==0?.15:0))*beat,beat*.85,melody[mode][(step+bar)%8],.09,0);
    if(mode>0) {
     Note((step+.5)*beat,beat*.38,root+24+(j%2==0?0:7),.055,0);
     Drum(step*beat,j%2==0,.1);Drum((step+.5)*beat,false,mode==2?.045:.02);
    }
   }
  }
  double peak=.001;foreach(double s in buffer) peak=Math.Max(peak,Math.Abs(s));
  using(var file=new BinaryWriter(File.Create(path))) {
   file.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));file.Write(36+buffer.Length*2);
   file.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));file.Write(16);file.Write((short)1);file.Write((short)1);
   file.Write(R);file.Write(R*2);file.Write((short)2);file.Write((short)16);
   file.Write(System.Text.Encoding.ASCII.GetBytes("data"));file.Write(buffer.Length*2);
   foreach(double s in buffer) file.Write((short)(s/peak*.72*32767));
  }
 }
}
'@
[DinerMusic]::Write((Join-Path $output 'casual.wav'),80,0)
[DinerMusic]::Write((Join-Path $output 'service.wav'),104,1)
[DinerMusic]::Write((Join-Path $output 'cooking.wav'),120,2)
Get-ChildItem -LiteralPath $output -Filter '*.wav' | Select-Object Name,Length
