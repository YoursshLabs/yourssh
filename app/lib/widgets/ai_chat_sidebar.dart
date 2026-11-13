import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/ai_provider_config.dart';
import '../models/chat_message.dart';
import '../providers/ai_chat_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'ys_form_controls.dart';

class AiChatSidebar extends StatefulWidget {
  final VoidCallback onClose;

  const AiChatSidebar({super.key, required this.onClose});

  @override
  State<AiChatSidebar> createState() => _AiChatSidebarState();
}

class _AiChatSidebarState extends State<AiChatSidebar> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<AiChatProvider>().send(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AiChatProvider>();

    return Container(
      width: 340,
      color: YsColors.sidebar,
      child: Column(
        children: [
          _buildHeader(context, provider),
          if (!provider.configured) _buildUnconfiguredBanner(),
          Expanded(child: _buildMessageList(provider)),
          _buildInput(provider),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AiChatProvider provider) {
    final configured = provider.configuredProviders;
    final active = configured.contains(provider.activeProvider)
        ? provider.activeProvider
        : (configured.isEmpty ? null : configured.first);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
      decoration: const BoxDecoration(
        color: YsColors.card,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          const Icon(FLucideIcons.bot, size: 16, color: YsColors.primary),
          const SizedBox(width: YsSpace.s2),
          // One Expanded group: a bare Flexible title next to a Spacer would
          // split the free width 50/50 and ellipsize the title needlessly.
          Expanded(
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'AI Assistant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: YsColors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (active != null) ...[
                  const SizedBox(width: YsSpace.s2),
                  SizedBox(
                    width: 112,
                    child: FSelect<AiProvider>.rich(
                      key: const ValueKey('ai-chat-provider'),
                      size: .sm,
                      control: .lifted(
                        value: active,
                        onChange: (p) {
                          if (p != null) {
                            context.read<AiChatProvider>().setActiveProvider(p);
                          }
                        },
                      ),
                      format: _providerLabel,
                      children: [
                        for (final p in configured)
                          FSelectItem<AiProvider>(
                            title: Text(_providerLabel(p)),
                            value: p,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (provider.messages.isNotEmpty)
            SettingsIconButton(
              icon: FLucideIcons.brushCleaning,
              tooltip: 'Clear chat',
              onPress: provider.clear,
            ),
          SettingsIconButton(
            icon: FLucideIcons.x,
            tooltip: 'Close',
            onPress: widget.onClose,
          ),
        ],
      ),
    );
  }

  String _providerLabel(AiProvider p) => switch (p) {
    AiProvider.anthropic => 'Anthropic',
    AiProvider.openai => 'OpenAI',
    AiProvider.gemini => 'Gemini',
  };

  Widget _buildUnconfiguredBanner() {
    return Container(
      margin: const EdgeInsets.all(YsSpace.s3),
      padding: const EdgeInsets.all(YsSpace.s3),
      decoration: BoxDecoration(
        color: YsColors.card,
        border: Border.all(color: YsColors.border),
        borderRadius: BorderRadius.circular(YsRadius.control),
      ),
      child: const Text(
        'Configure API keys in Settings → AI Providers to enable AI assistance.',
        style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMessageList(AiChatProvider provider) {
    if (provider.messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(YsSpace.s5),
          child: Text(
            'Ask anything about SSH commands, debugging errors, or DevOps tasks.',
            style: TextStyle(color: YsColors.mutedForeground, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(YsSpace.s2),
      itemCount: provider.messages.length,
      itemBuilder: (_, i) => _buildMessage(provider.messages[i]),
    );
  }

  Widget _avatar(IconData icon, Color background, Color foreground) =>
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: foreground),
      );

  Widget _buildMessage(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YsSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _avatar(FLucideIcons.bot, YsColors.primary, YsColors.primaryForeground),
            const SizedBox(width: YsSpace.s2),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: YsSpace.s3,
                vertical: YsSpace.s2,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? YsColors.primary.withValues(alpha: 0.15)
                    : YsColors.card,
                border: Border.all(color: YsColors.border),
                borderRadius: BorderRadius.circular(YsRadius.control),
              ),
              child: msg.isStreaming
                  ? const FCircularProgress(size: .sm)
                  : MarkdownBody(
                      data: msg.content,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: YsColors.foreground,
                          fontSize: 13,
                          height: 1.5,
                        ),
                        code: const TextStyle(
                          color: YsColors.accentText,
                          fontFamily: kYsMonoFontFamily,
                          fontFamilyFallback: kYsMonoFontFallback,
                          fontSize: 12,
                          backgroundColor: YsColors.background,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: YsColors.background,
                          border: Border.all(color: YsColors.border),
                          borderRadius: BorderRadius.circular(YsRadius.control),
                        ),
                      ),
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: YsSpace.s2),
            _avatar(FLucideIcons.user, YsColors.card, YsColors.mutedForeground),
          ],
        ],
      ),
    );
  }

  KeyEventResult _onInputKey(KeyEvent event, bool canSend) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Shift+Enter keeps the default newline; IME composition owns Enter.
    if (HardwareKeyboard.instance.isShiftPressed ||
        _controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && canSend) _send();
    return KeyEventResult.handled;
  }

  Widget _buildInput(AiChatProvider provider) {
    final canSend = provider.configured && !provider.loading;
    return Container(
      padding: const EdgeInsets.all(YsSpace.s2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            // Enter sends, Shift+Enter inserts a newline. The Focus sits above
            // the text field so it sees key events bubbling up from it.
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, event) => _onInputKey(event, canSend),
              child: FTextField(
                key: const ValueKey('ai-chat-input'),
                control: .managed(controller: _controller),
                maxLines: 3,
                minLines: 1,
                hint: 'Ask a command question…',
                onSubmit: (_) => canSend ? _send() : null,
              ),
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          SettingsIconButton(
            icon: FLucideIcons.send,
            tooltip: 'Send',
            onPress: canSend ? _send : null,
          ),
        ],
      ),
    );
  }
}
