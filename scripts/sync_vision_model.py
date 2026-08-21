#!/usr/bin/env python3
"""v3.0.27：视觉模型同步脚本
读取 iOS App 的 UserDefaults（通过 iTunes File Sharing 或共享目录），
将视觉模型设置同步到 wechat-profile config.yaml。

使用方式：
1. App 端保存视觉模型时写入 UserDefaults key: qingliao_vision_model
2. NAS 端定期运行此脚本，或由后端 channel_api.py 在 /api/channel/vision-model GET 时调用

数据流：App UserDefaults → NAS sync_vision_model.py → wechat-profile config.yaml
"""
import os, json, re

# iOS App 的 UserDefaults plist 路径（通过 iTunes File Sharing 导出）
# 或者通过 Hermes relay 读取 App 发送的配置
APP_DEFAULTS_PATH = os.environ.get(
    "QL_APP_DEFAULTS_PATH",
    "/volume1/docker/hermes/微信文件/轻聊app/vision_config.json",
)

# wechat-profile 的 config.yaml
PROFILE_CFG = os.environ.get(
    "QL_WECHAT_PROFILE_CFG",
    "/volume1/docker/hermes/hermes-data/profiles/wechat-profile/config.yaml",
)

# 支持的 provider（与 wechat-profile providers 段对齐）
VALID_PROVIDERS = {
    "deepseek", "stepfun", "xiaomi", "opencode", "opencode-apple",
    "ollama", "sensenova", "zai", "glm", "kimi", "openrouter", "custom",
}


def read_vision_config():
    """从 App 的 JSON 配置文件读取视觉模型设置"""
    try:
        with open(APP_DEFAULTS_PATH, encoding="utf-8") as f:
            cfg = json.load(f)
        model = cfg.get("vision_model", "")
        provider = cfg.get("vision_provider", "")
        base_url = cfg.get("vision_base_url", "")
        if not model:
            return None
        return {"model": model, "provider": provider, "base_url": base_url}
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def read_profile_vision():
    """读 wechat-profile config.yaml 的 auxiliary.vision 段"""
    try:
        with open(PROFILE_CFG, encoding="utf-8") as f:
            lines = f.read().splitlines()
        model = provider = base_url = None
        in_aux = False
        in_vision = False
        for ln in lines:
            s = ln.strip()
            indent = len(ln) - len(ln.lstrip())
            if s == "auxiliary:" and indent == 0:
                in_aux = True
                continue
            if in_aux and indent == 0 and s and not s.startswith("#"):
                in_aux = False
            if in_aux and indent == 2 and s == "vision:":
                in_vision = True
                continue
            if in_vision and indent == 2 and s and not s.startswith("#"):
                in_vision = False
            if in_vision and indent == 4:
                if s.startswith("model:"):
                    model = s.split(":", 1)[1].strip().strip("\"'")
                elif s.startswith("provider:"):
                    provider = s.split(":", 1)[1].strip().strip("\"'")
                elif s.startswith("base_url:"):
                    base_url = s.split(":", 1)[1].strip().strip("\"'")
        return {"model": model, "provider": provider, "base_url": base_url}
    except Exception:
        return {"model": None, "provider": None, "base_url": None}


def write_profile_vision(provider, model):
    """写 wechat-profile config.yaml 的 auxiliary.vision 段"""
    try:
        with open(PROFILE_CFG, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        lines = []

    out = []
    in_aux = False
    skip_vision = False
    found_vision = False

    for ln in lines:
        s = ln.strip()
        indent = len(ln) - len(ln.lstrip())

        if s == "auxiliary:" and indent == 0:
            in_aux = True

        if in_aux and indent == 0 and s and s != "auxiliary:" and not s.startswith("#"):
            in_aux = False

        if in_aux and indent == 2 and s == "vision:":
            skip_vision = True
            found_vision = True
            if model:
                out.append("  vision:")
                out.append("    provider: %s" % provider)
                out.append("    model: %s" % model)
            continue

        if skip_vision and indent == 2 and s and not s.startswith("#"):
            skip_vision = False

        if skip_vision:
            continue

        out.append(ln)

    # 如果没有找到 vision 块但在 auxiliary 段内，追加
    if not found_vision and in_aux and model:
        out.append("  vision:")
        out.append("    provider: %s" % provider)
        out.append("    model: %s" % model)

    # 如果连 auxiliary 段都没有，创建
    if not in_aux and model and "auxiliary:" not in [x.strip() for x in out]:
        out.append("")
        out.append("auxiliary:")
        out.append("  vision:")
        out.append("    provider: %s" % provider)
        out.append("    model: %s" % model)

    with open(PROFILE_CFG, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def sync():
    """同步视觉模型：App 设置 → wechat-profile config"""
    app_cfg = read_vision_config()
    profile_cfg = read_profile_vision()

    if app_cfg is None:
        print("[sync] 无视觉模型配置，跳过")
        return False

    # 比较是否需要更新
    if (app_cfg["model"] == profile_cfg.get("model")
            and app_cfg["provider"] == profile_cfg.get("provider")):
        print("[sync] 视觉模型已同步，无需更新")
        return False

    # 写入
    provider = app_cfg["provider"] or "opencode"
    if provider not in VALID_PROVIDERS:
        provider = "opencode"

    write_profile_vision(provider, app_cfg["model"])
    print("[sync] 视觉模型已同步: %s / %s" % (provider, app_cfg["model"]))
    return True


if __name__ == "__main__":
    sync()
