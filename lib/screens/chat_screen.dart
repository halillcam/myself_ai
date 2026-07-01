import 'package:flutter/material.dart';

import '../services/gemma_service.dart';
import '../model/chat_message_model.dart';

class ChatScreen extends StatefulWidget {
  final GemmaService gemmaService;
  const ChatScreen({super.key, required this.gemmaService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;

  GemmaService get _service => widget.gemmaService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.tryAutoLoad();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isGenerating) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(const ChatMessage(text: '', isUser: false));
      _isGenerating = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      await for (final token in _service.askStream(text)) {
        buffer.write(token);
        setState(() {
          _messages[_messages.length - 1] = ChatMessage(text: buffer.toString(), isUser: false);
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages[_messages.length - 1] = ChatMessage(text: 'Hata: $e', isUser: false);
      });
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _resetChat() async {
    setState(() => _messages.clear());
    await _service.resetChat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local AI Chat'),
        actions: [
          if (_service.status == GemmaStatus.ready) ...[
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Sohbeti temizle',
              onPressed: _isGenerating ? null : _resetChat,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Farklı model seç',
              onPressed: _isGenerating ? null : _service.pickAndInstall,
            ),
          ],
        ],
      ),
      body: switch (_service.status) {
        GemmaStatus.ready => _buildChat(),
        GemmaStatus.installing => _buildSetupCard(
          icon: Icons.downloading,
          message: 'Model yükleniyor... %${_service.installProgress}',
          showProgress: true,
        ),
        GemmaStatus.pickingFile => _buildSetupCard(
          icon: Icons.folder_open,
          message: 'Dosya seçiliyor...',
          showProgress: true,
        ),
        GemmaStatus.error => _buildSetupCard(
          icon: Icons.error_outline,
          message: 'Hata oluştu:\n${_service.errorMessage}',
          isError: true,
        ),
        GemmaStatus.idle => _buildSetupCard(
          icon: Icons.smart_toy_outlined,
          message: 'Cihazındaki Gemma model dosyasını (.bin) seçerek başla.',
        ),
      },
    );
  }

  Widget _buildSetupCard({
    required IconData icon,
    required String message,
    bool showProgress = false,
    bool isError = false,
  }) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            if (showProgress)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _service.pickAndInstall,
                icon: const Icon(Icons.folder_open),
                label: const Text('Model Dosyasını Seç'),
              ),
            if (isError) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _service.pickAndInstall,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'Merhaba! Sana nasıl yardımcı olabilirim? 👋',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildBubble(_messages[index]),
                ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: msg.text.isEmpty
            ? SizedBox(width: 24, height: 16, child: _ThinkingDots())
            : Text(
                msg.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isUser ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isGenerating,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Bir şeyler yaz...',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isGenerating ? null : _send,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final value = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = value < 0.5 ? value * 2 : (1 - value) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
