import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api_exception.dart';
import '../../core/constants.dart';
import '../../providers.dart';
import '../../widgets/states.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(_email.text.trim(), _password.text);
      ref.invalidate(countsProvider);
      if (!mounted) return;
      showToast(context, '登录成功');
      context.canPop() ? context.pop() : context.go('/me');
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset('assets/icon/icon.png',
                            width: 96, height: 96),
                      ),
                      const SizedBox(height: 8),
                      Text('Iwara',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.primary)),
                      const SizedBox(height: 8),
                      Text('使用 iwara.tv 账号登录',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.hintColor)),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        // 官网登录接口的 email 字段同时接受邮箱和用户名
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '邮箱或用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '请输入邮箱或用户名'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? '请输入密码' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('登录'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => launchUrl(
                                Uri.parse('${IwaraConst.siteUrl}/register'),
                                mode: LaunchMode.externalApplication),
                            child: const Text('注册账号'),
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                                Uri.parse(
                                    '${IwaraConst.siteUrl}/forgot-password'),
                                mode: LaunchMode.externalApplication),
                            child: const Text('忘记密码'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '无法连接时，请在「设置 → 网络代理」中配置代理。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                      TextButton(
                        onPressed: () => context.push('/settings'),
                        child: const Text('打开设置'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
