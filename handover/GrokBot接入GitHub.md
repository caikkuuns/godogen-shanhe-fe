# Grok Bot 怎么接上 GitHub

## 凭据

本仓库已配置 **deploy key**（Settings → Deploy keys → `grokbot-deploy-write`，已勾 Allow write access，`verified: true`），**只能动这一个仓库**。

私钥由萧炎交给用户，**不进仓库**。拿到后：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# 把私钥内容存成 ~/.ssh/godogen_shanhe
chmod 600 ~/.ssh/godogen_shanhe
export GIT_SSH_COMMAND="ssh -i ~/.ssh/godogen_shanhe -o IdentitiesOnly=yes"
git clone git@github.com:caikkuuns/godogen-shanhe-fe.git
```

之后 `git push` 直接可用。

## 规矩

- **不要推 master**。开 `grokbot/xxx` 分支，推完开 PR。
- 每次改完在 `handover/` 写一篇 `交接-YYYYMMDD-grokbot-主题.md`，模板见 `交接说明模板.md`。
- 私钥不要再复制到别处，不写进任何提交或日志。
- 撤销：Settings → Deploy keys 删掉 `grokbot-deploy-write`，立刻失效。

## 备选路

若 Grok Bot 那台机器已有自己的 GitHub 凭据，也可以由仓库主人加成 collaborator。两条路选一条，别都开。
