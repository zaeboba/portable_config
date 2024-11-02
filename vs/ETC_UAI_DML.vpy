### https://github.com/hooke007/MPV_lazy/wiki/3_K7sfunc
### Использование пользовательской AI-модели масштабирования, оптимизированной для DX12 графических карт

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f

clip = video_in

############
# 用户选项 #
############

H_Pre = 720
Model = "Sirosky_AniScale2S_Compact_x2_fp32_op17.onnx"
Gpu = 0
Gpu_T = 2
H_Max = 1440
Lk_Fmt = False
## 整数，预降低处理源高度
## 使用的模型（限定fp32类模型）
## 使用的显卡序号，0为排序一号
## <1|2|3> 使用的显卡线程数
## 整数，输出高度限制（填你的显示器高度）
## <True|False> 是否锁定像素格式为yuv420p8

ret = k7f.FMT_CTRL(clip, h_max=1200, h_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.UAI_DML(clip, clamp=False, model_pth=Model, gpu=Gpu, gpu_t=Gpu_T)
clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0)

clip.set_output()
