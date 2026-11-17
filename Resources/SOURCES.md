# KeyTone 1.1 音源出处与处理

新版采用 Mechvibes 官方仓库随项目提供的逐键录音和配置。上游固定提交：`16afce45bd7cf12be399e2d1a8d20f221067f534`。项目采用 MIT 授权，完整版权和授权正文随应用保存在 LICENSE-Mechvibes.txt。这里只复用音频与键位标注，播放器与界面仍为 KeyTone 的原生实现。

上游：[Mechvibes 音源目录](https://github.com/hainguyents13/mechvibes/tree/16afce45bd7cf12be399e2d1a8d20f221067f534/soundpacks/keyboard)；[MIT LICENSE](https://github.com/hainguyents13/mechvibes/blob/16afce45bd7cf12be399e2d1a8d20f221067f534/LICENSE)。每一组的准确目录还在 profiles.json 和 sources.json 中，应用内可直接打开。

## 十组音色

水晶紫轴（默认）、Topre 紫轴、奥利奥轴、Cherry 黑轴/PBT、Cherry 红轴/ABS、Cherry 茶轴/PBT、Cherry 黑轴/ABS、Cherry 茶轴/ABS、Cherry 青轴/PBT、Cherry 青轴/ABS。

ABS/PBT 条目是上游两套不同录音，不把全部声学差异归因于键帽材料。保留青轴作为偏好明显咔嗒声的选择，将圆润的录音排在前面。

## 真实键宽差异

每组使用 KeyF / KeyJ / KeyD / KeyK 四个普通键片段，以及 Tab、CapsLock、ShiftLeft、ShiftRight、Backspace、Enter、Space 七个各自有明确标注的片段。普通键随机轮换，大键始终选取自己的实录，仅允许整体设置启用的微小增益变化。没有给大键强行降调、延长声音或叠加别的键盘的空格声。

Keychron 对其键盘结构的说明指出，Shift、Enter、Backspace 与空格等大键使用稳定器。真实声音同时受键帽、稳定器、外壳和装配影响。Tab 和 Caps Lock 不能一概当成带稳定器的大键。因此采用对应录音里的真实差异，不用“越宽就越低”的规则替代。[Keychron 结构说明](https://www.keychron.com/blogs/news/the-design-details-of-our-keychron-low-profile-keyboard-stabilizers)。

## 采样处理

输入是上游仓库发布的 Ogg Vorbis 文件（44.1 或 48 kHz），不是无损录音母带，不能将 WAV 输出说成音源无损升级。新版的改善来自逐键定位、正确区分按下/回弹、起音对齐与更适度的清理。

每个按键使用上游 timing 的第一段作为按下声；已检查普通键和空格的波形，第二段对应回弹。65 Hz 高通去除次声和 DC；非常轻的高频衰减最高约 2.85 dB；去掉按键主体之前的空白或轻微滑动声；保留有效衰减并平滑结束。没有移调、合成稳定器、人工加低音或将所有大键单独拉到同一响度。

同一套键盘使用统一增益，使键间相对动态保留。“真实大键声音”默认开启，可以关闭作对比。全部文件最终以单声道 48 kHz / 16-bit PCM 存储，启动时载入，不在击键路径中解码。

源码 AudioSources 中包含原始逐键配置及下载地址、SHA-256；Resources/sample-audit.json 记录每个输出文件对应的原始键、原始时间区间、裁剪偏移、增益和 SHA-256，可逐项追溯。原始长录音只保留在开发 work 目录，不打进 App。

早期开发阶段使用过的 Freesound 音源已移除，不包含在本公开仓库或当前应用中。
