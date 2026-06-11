# Backlog

## v1.0 Release Checklist

### Blocking

- [ ] **R1: Fix bootstrap.sh bugs** (từ code review)
  - `trap` không dọn `PROJECT_DIR` khi lỗi giữa chừng → user bị kẹt khi re-run
  - `bash install.sh </dev/tty` crash trên CI / môi trường không có `/dev/tty`
  - `git commit` fail trên máy chưa cấu hình `user.name`/`user.email`
  - `EXTRACTED=$(ls "$TMP_DIR")` vỡ nếu tarball extract ra nhiều entry (fix: dùng `tar --strip-components=1`)
  - `install.sh:105` không có fallback khi Docker daemon chưa bật (storage path)
- [x] **R2: Tắt dev-mode settings trong docker-compose** — `HASURA_GRAPHQL_DEV_MODE=true` và `HASURA_GRAPHQL_ENABLE_CONSOLE=true` không được bật khi deploy production; document rõ hoặc tách `.env.prod`
- [x] **R3: Mở rộng health endpoint** — `GET /health` hiện chỉ trả `{status: "ok"}`, không verify Hasura hay DB còn sống; thêm dependency health check
- [ ] **R4: Thêm release workflow vào CI** — tạo job tự động tag + publish GitHub Release khi merge vào main
- [ ] **R5: Publish tag v1.0.0 + GitHub Release** — hiện bootstrap.sh luôn fallback về `main` vì chưa có release nào; user không có version pinning

### Nice-to-have

- [ ] **R6: `template/` directory separation** (xem section bên dưới) — giải quyết trước khi user base lớn
- [ ] **R7: Thêm lint job vào CI** — ESLint đã cấu hình nhưng không được enforce trong pipeline
- [ ] **R8: CONTRIBUTING.md + TROUBLESHOOTING.md** — người dùng gặp lỗi không biết báo ở đâu

---

## Planned: bootstrap.sh — `template/` directory separation

**Problem:** `bootstrap.sh` hiện dùng hardcoded exclude list (`STRATUM_INTERNAL`) để xóa file internal khỏi project của user. Dev thêm file internal mới sẽ không biết phải update list này.

**Solution:** Dùng thư mục `template/` — bootstrap chỉ lấy những gì bên trong đó, mọi thứ ngoài tự động excluded. Không cần maintain list.

```
stratum/
├── template/       ← CHỈ cái này đến tay user
│   ├── hasura/
│   ├── nestjs/
│   ├── docs/
│   └── ...
├── .github/        ← tự động excluded
├── tests/          ← tự động excluded
└── bootstrap.sh    ← tự động excluded
```

**Scope:** restructure repo, update `bootstrap.sh` để extract từ `template/` thay vì root.
