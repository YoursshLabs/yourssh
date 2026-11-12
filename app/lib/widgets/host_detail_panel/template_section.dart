part of 'host_detail_panel.dart';

/// SESSION TEMPLATE (SSH only): working directory, env vars, startup snippet
/// and the per-host terminal theme / font / size / TERM / tmux overrides
/// (`null` = follow the global setting).
class _TemplateSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _TemplateSection({required this.form});

  String? _validateEnvKey(String? v) {
    final k = v?.trim() ?? '';
    if (k.isEmpty) return null;
    if (!ShellIntegrationService.isValidEnvKey(k)) return 'A–Z, 0–9, _ only';
    // A map literal would silently keep only the last duplicate — surface
    // it instead.
    final dups = form._envRows.where((r) => r.key.text.trim() == k).length;
    return dups > 1 ? 'Duplicate name' : null;
  }

  String? _validateFontSize(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final d = double.tryParse(t);
    return (d == null || d < 6 || d > 40) ? '6–40' : null;
  }

  void _removeEnvRow(int i) => form._set(() {
    final row = form._envRows.removeAt(i);
    // Dispose after the frame: the row's fields are still mounted during
    // this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      row.key.dispose();
      row.value.dispose();
    });
  });

  @override
  Widget build(BuildContext context) {
    final rows = form._envRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('SESSION TEMPLATE'),
        _Field(
          key: const ValueKey('template-workdir-field'),
          controller: form._workingDirCtrl,
          hint: 'Working directory (bash/zsh only)',
          icon: FLucideIcons.folderOpen,
          onSubmit: form._submit,
        ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: ObjectKey(rows[i]),
            padding: const EdgeInsets.only(top: YsSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _Field(
                    key: ValueKey('env-key-$i'),
                    controller: rows[i].key,
                    hint: 'NAME',
                    icon: FLucideIcons.braces,
                    onSubmit: form._submit,
                    validator: _validateEnvKey,
                  ),
                ),
                const SizedBox(width: YsSpace.s2),
                Expanded(
                  flex: 3,
                  child: _Field(
                    key: ValueKey('env-value-$i'),
                    controller: rows[i].value,
                    hint: 'value',
                    onSubmit: form._submit,
                  ),
                ),
                Tooltip(
                  message: 'Remove variable',
                  excludeFromSemantics: true,
                  child: FButton.icon(
                    variant: .ghost,
                    size: .sm,
                    semanticsLabel: 'Remove variable',
                    onPress: () => _removeEnvRow(i),
                    child: const Icon(FLucideIcons.x),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FButton(
            variant: .ghost,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            prefix: const Icon(FLucideIcons.plus),
            onPress: () => form._set(
              () => rows.add((
                key: TextEditingController(),
                value: TextEditingController(),
              )),
            ),
            child: _buttonText('Add env variable'),
          ),
        ),
        _fieldGap,
        FTextFormField.multiline(
          key: const ValueKey('template-snippet-field'),
          control: .managed(controller: form._startupSnippetCtrl),
          minLines: 2,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          hint:
              'Startup snippet — typed into the shell '
              'after connect. Skipped when tmux is on.',
          style: .delta(
            contentTextStyle: .delta([
              .all(
                .delta(
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
            ]),
          ),
          prefixBuilder: _prefixIcon(FLucideIcons.play),
        ),
        _fieldGap,
        _Select<String?>(
          key: const ValueKey('template-theme-select'),
          icon: FLucideIcons.palette,
          value: form._templateTheme,
          options: [
            (null, 'Theme: follow global'),
            for (final name in kTerminalThemeNames) (name, name),
          ],
          onChanged: (v) => form._set(() => form._templateTheme = v),
        ),
        _fieldGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Select<String?>(
                key: const ValueKey('template-font-select'),
                icon: FLucideIcons.type,
                value: form._templateFont,
                options: [
                  (null, 'Font: follow global'),
                  for (final f in kBundledTerminalFonts) (f, f),
                ],
                onChanged: (v) => form._set(() => form._templateFont = v),
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            SizedBox(
              width: 68,
              child: _Field(
                key: const ValueKey('template-font-size-field'),
                controller: form._fontSizeCtrl,
                hint: 'size',
                keyboardType: TextInputType.number,
                onSubmit: form._submit,
                validator: _validateFontSize,
              ),
            ),
          ],
        ),
        _fieldGap,
        _Select<String?>(
          key: const ValueKey('template-term-select'),
          icon: FLucideIcons.squareTerminal,
          value: form._templateTermType,
          options: [
            (null, 'TERM: follow global'),
            for (final t in kTermTypes) (t, t),
          ],
          onChanged: (v) => form._set(() => form._templateTermType = v),
        ),
        _fieldGap,
        _Select<bool?>(
          key: const ValueKey('template-tmux-select'),
          icon: FLucideIcons.layoutGrid,
          value: form._tmuxOverride,
          options: const [
            (null, 'tmux: follow global'),
            (true, 'tmux: always on'),
            (false, 'tmux: always off'),
          ],
          onChanged: (v) => form._set(() => form._tmuxOverride = v),
        ),
      ],
    );
  }
}
