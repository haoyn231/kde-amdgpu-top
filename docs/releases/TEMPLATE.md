# kde-amdgpu-top @VERSION@

> 通用 Release 模板。若不存在 `docs/releases/v@VERSION@.md`，发布时使用本文件并把 `@VERSION@` 替换为版本号。

## 更新内容 / What's Changed

- 请在此补充本版本的变更 / Add the changes for this release here
- See the commit history for the full list

## 安装教程（KDE Plasma 6）

### 环境要求

- KDE Plasma 6（Qt 6.5+）
- [amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top) ≥ 0.9
- python3（只用标准库）

### 从 Release 安装（推荐）

1. 下载本页附件中的 `kde-amdgpu-top-v@VERSION@.tar.gz` 与 `.sha256` 文件。
2. 校验并解压到当前用户的 Plasma 小程序目录：
   ```bash
   sha256sum -c kde-amdgpu-top-v@VERSION@.tar.gz.sha256
   mkdir -p ~/.local/share/plasma/plasmoids
   tar -xzf kde-amdgpu-top-v@VERSION@.tar.gz -C ~/.local/share/plasma/plasmoids
   ```
3. 重新加载 Plasma：
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. 右键面板 → **进入编辑模式**（或「添加小组件」）→ 搜索 **AMD GPU 监视器** / **AMD GPU Monitor** → 拖到面板。
5. 点击面板里的 GPU 或显存数字打开详情。

### 从源码安装

```bash
sudo pacman -S --needed plasma-desktop amdgpu_top python
git clone https://github.com/haoyn231/kde-amdgpu-top.git
cd kde-amdgpu-top
./install.sh
systemctl --user restart plasma-plasmashell.service
```

### 卸载

```bash
rm -rf ~/.local/share/plasma/plasmoids/org.hao.amdgputop
systemctl --user restart plasma-plasmashell.service
```

## Installation (KDE Plasma 6)

### Requirements

- KDE Plasma 6 (Qt 6.5+)
- [amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top) ≥ 0.9
- python3 (standard library only)

### Install from the release (recommended)

1. Download `kde-amdgpu-top-v@VERSION@.tar.gz` and `kde-amdgpu-top-v@VERSION@.tar.gz.sha256` from the assets below.
2. Verify and extract the archive into your user Plasma widget directory:
   ```bash
   sha256sum -c kde-amdgpu-top-v@VERSION@.tar.gz.sha256
   mkdir -p ~/.local/share/plasma/plasmoids
   tar -xzf kde-amdgpu-top-v@VERSION@.tar.gz -C ~/.local/share/plasma/plasmoids
   ```
3. Reload Plasma:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. Right-click the panel → **Enter Edit Mode** (or **Add Widgets**) → search for **AMD GPU Monitor** → drag it onto the panel.
5. Click the GPU or VRAM number in the panel to open the popup.

### Build from source

```bash
sudo pacman -S --needed plasma-desktop amdgpu_top python
git clone https://github.com/haoyn231/kde-amdgpu-top.git
cd kde-amdgpu-top
./install.sh
systemctl --user restart plasma-plasmashell.service
```

### Uninstall

```bash
rm -rf ~/.local/share/plasma/plasmoids/org.hao.amdgputop
systemctl --user restart plasma-plasmashell.service
```
