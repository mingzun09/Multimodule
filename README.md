# Multimodule
Module system is made to be modular and customizable

## 如何使用该模块

首先你需要Fok这个项目，在你fok的仓库中进行操作。
你可以把你想要打包刷入的模块存放在"\modules\"目录中
将想要打包安装的"APK"存放在"\system\priv-app\"目录中
然后使用"Actions"构建你的一体化模块，就可以使用了。

## 自定义配置或者操作

如果你明白该怎么去做的情况下。
你可以编辑'customize.sh'文件对其添加或修改内容来实现一些事情。

## customize.sh注意事项

因为添加了安装APK相关的代码，所以我也添加了拦截REC(恢复模式下）禁止安装此模块的代码。
比如你使用TWRP时刷入这个模块，那样会导致有关的apk安装失败，并产生一些未知问题。
