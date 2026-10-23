# Tide English engineering conventions

- This is an independent repository. Do not modify neighboring projects or install/uninstall device apps unless the task calls for it.
- Use Tide English for display text, TideEnglish for code/modules, cn.gd306.tideenglish for Kotlin namespace and TIDE_ENGLISH_* for build settings. Update project references, resources, fixtures and CI together.
- Never commit keys, SMTP secrets, tokens, signing material, local configuration, caches or learning archives. Use synthetic credentials in tests.
- Hosted accounts, trials and purchases remain disabled by default. Email identity must not gate learning or enable learning sync.
- Preserve licenses and third-party notices. Example store IDs, prices and deployment templates are not production configuration.
- Run root tools from the root. Generate Xcode changes with tools/generate_project.py. Do not hardcode personal signing teams.
- Keep Swift/Kotlin teaching, archive and language contracts compatible. Run affected tests and checks after moves; do not weaken assertions to pass a rename.
- Report hardware/live checks separately from offline tests and builds.
- Evaluate app/server compatibility. Deploy only when required and authorized, with backups and rollback. A source rebuild does not change deployed services.
