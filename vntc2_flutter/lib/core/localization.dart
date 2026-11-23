import 'package:flutter/material.dart';

import 'models.dart';

const supportedAppLocales = <Locale>[Locale('zh', 'CN'), Locale('en')];

Locale localeForLanguage(AppLanguage language) {
  return switch (language) {
    AppLanguage.zhHans => const Locale('zh', 'CN'),
    AppLanguage.en => const Locale('en'),
  };
}

AppLanguage appLanguageOf(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode.toLowerCase() == 'en'
      ? AppLanguage.en
      : AppLanguage.zhHans;
}

String tr(BuildContext context, String zhHans, String en) {
  return trByLanguage(appLanguageOf(context), zhHans, en);
}

String trByLanguage(AppLanguage language, String zhHans, String en) {
  return language == AppLanguage.en ? en : zhHans;
}

String languageDisplayName(AppLanguage language) {
  return switch (language) {
    AppLanguage.zhHans => '简体中文',
    AppLanguage.en => 'English',
  };
}

String formatCloseActionLabel(CloseAction action, AppLanguage language) {
  return switch (action) {
    CloseAction.close => trByLanguage(language, '直接关闭', 'Close app'),
    CloseAction.tray => trByLanguage(language, '最小化到托盘', 'Minimize to tray'),
    CloseAction.ask => trByLanguage(language, '每次询问', 'Ask every time'),
  };
}

String appTitleForLanguage(AppLanguage language) {
  return trByLanguage(language, 'VNT虚拟组网2.0', 'VNTC 2.0 Client');
}

String defaultPeerName(AppLanguage language) {
  return trByLanguage(language, '未命名节点', 'Unnamed peer');
}

String defaultOperationReason(AppLanguage language) {
  return trByLanguage(language, '未知错误', 'Unknown error');
}
