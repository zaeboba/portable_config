### https://github.com/hooke007/MPV_lazy/wiki/3_K7sfunc
### Преобразование источника с 25 или 30 кадрами в 24 кадра в секунду

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# 用户选项 #
############

Ivtc_M = 1
## <1|2> ivtc模式

clip = k7f.IVTC_STD(clip, fps_in=container_fps, ivtc_m=Ivtc_M)

clip.set_output()
