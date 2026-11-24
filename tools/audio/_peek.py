import sys; sys.path.insert(0,'tools/audio')
import analyze as A, synth as S
out=sys.argv[1]; ims=[]
for f in sys.argv[2:]:
    x=S.read_audio("assets/generated/audio/"+f)
    ims.append(A.spectrogram_image(x,f,width=440,height=200))
A.sheet(ims,3).save(out)
