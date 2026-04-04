# NanoSwitch — CLAUDE.md

- **プラットフォーム**: macOS
- **リポジトリ**: https://github.com/LifeDesignStudio/NanoSwitch
- **GitHub Projects**: https://github.com/users/LifeDesignStudio/projects/1

---

## セッションプロトコル

### 開始時（自動実行）
1. `DEVELOPMENT_CHECKPOINT.md` を読み、現在の技術状態・前回の作業内容を把握する
2. `gh issue list --repo LifeDesignStudio/NanoSwitch --state open --json number,title` で未完了タスクを確認する
3. In Progress の Issue を優先して着手する

### 終了時（「セッション終了」「ボードを更新」と言われたら実行）
1. 完了した Issue を Close する（Kanban が自動で Done に移動）
2. 新しいバグ・TODO は Issue を作成してプロジェクトに追加する
3. `DEVELOPMENT_CHECKPOINT.md` の「次のステップ」セクションを現状に合わせて更新する

Issue 作成コマンド:
```bash
gh issue create --repo LifeDesignStudio/NanoSwitch --title "タスク名" --body "詳細"
gh project item-add 1 --owner LifeDesignStudio --url <issue-url>
```

---

## 注意事項
- コードを変更したら必ず `git commit` する（自動で GitHub へ push される）
- プライベート API（CGS / AXUIElement）の変更は macOS バージョンとの互換性を必ず確認すること
- Sandbox は**無効**のまま維持すること（CGEventTap に必要）
