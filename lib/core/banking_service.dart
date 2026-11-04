import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class BankAppInfo {
  final String id;
  final String name;
  final String shortName;
  final String packageName;
  final String scheme;
  final Color brandColor;
  final IconData icon;

  const BankAppInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.packageName,
    required this.scheme,
    required this.brandColor,
    this.icon = Icons.account_balance,
  });
}

const List<BankAppInfo> kSupportedBanks = [
  BankAppInfo(
    id: 'mbbank',
    name: 'MBBank (Quân Đội)',
    shortName: 'MBBank',
    packageName: 'com.mbmobile',
    scheme: 'mbmobile://',
    brandColor: Color(0xFF1E4399),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'vcb',
    name: 'Vietcombank (VCB Digibank)',
    shortName: 'Vietcombank',
    packageName: 'com.VCB',
    scheme: 'vcb://',
    brandColor: Color(0xFF005B27),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'techcombank',
    name: 'Techcombank Mobile',
    shortName: 'Techcombank',
    packageName: 'com.techcombank.mobile',
    scheme: 'techcombank://',
    brandColor: Color(0xFFEE2E24),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'momo',
    name: 'Ví MoMo',
    shortName: 'MoMo',
    packageName: 'com.mservice.momotransfer',
    scheme: 'momo://',
    brandColor: Color(0xFFA50064),
    icon: Icons.account_balance_wallet,
  ),
  BankAppInfo(
    id: 'bidv',
    name: 'BIDV SmartBanking',
    shortName: 'BIDV',
    packageName: 'com.vnpay.bidv',
    scheme: 'bidvsmartbanking://',
    brandColor: Color(0xFF0F75BC),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'tpbank',
    name: 'TPBank Mobile',
    shortName: 'TPBank',
    packageName: 'com.tpb.mb.gprsandroid',
    scheme: 'tpbank://',
    brandColor: Color(0xFF7B2082),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'vpbank',
    name: 'VPBank NEO',
    shortName: 'VPBank',
    packageName: 'com.vnpay.vpbankonline',
    scheme: 'vpbank://',
    brandColor: Color(0xFF007E33),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'acb',
    name: 'ACB ONE',
    shortName: 'ACB',
    packageName: 'mobile.acb.com.vn',
    scheme: 'acb://',
    brandColor: Color(0xFF005EA6),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'zalopay',
    name: 'ZaloPay',
    shortName: 'ZaloPay',
    packageName: 'vn.com.vng.zalopay',
    scheme: 'zalopay://',
    brandColor: Color(0xFF0068FF),
    icon: Icons.account_balance_wallet,
  ),
  BankAppInfo(
    id: 'viettelmoney',
    name: 'Viettel Money',
    shortName: 'Viettel Money',
    packageName: 'com.bplus.vtpay',
    scheme: 'viettelmoney://',
    brandColor: Color(0xFFE60000),
    icon: Icons.account_balance_wallet,
  ),
];

class BankingAppService {
  /// Kiểm tra xem ứng dụng ngân hàng có mở được trên máy không.
  static Future<bool> isBankInstalled(BankAppInfo bank) async {
    try {
      final uri = Uri.parse(bank.scheme);
      return await canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Lọc và sắp xếp: Đưa các app ngân hàng đã cài trên thiết bị lên đầu danh sách.
  static Future<List<BankAppInfo>> getPrioritizedBanks() async {
    final installed = <BankAppInfo>[];
    final notInstalled = <BankAppInfo>[];

    for (final bank in kSupportedBanks) {
      final canOpen = await isBankInstalled(bank);
      if (canOpen) {
        installed.add(bank);
      } else {
        notInstalled.add(bank);
      }
    }

    return [...installed, ...notInstalled];
  }

  /// Mở ứng dụng ngân hàng và tự động sao chép nội dung chuyển khoản vào Clipboard.
  static Future<bool> openBankApp({
    required BankAppInfo bank,
    required String transferNote,
  }) async {
    // 1. Tự động sao chép nội dung chuyển khoản vào Clipboard
    if (transferNote.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: transferNote));
    }

    // 2. Thử kích hoạt App Scheme
    final schemeUri = Uri.parse(bank.scheme);
    if (await canLaunchUrl(schemeUri)) {
      return await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
    }

    // 3. Fallback: Mở Google Play Store để cài đặt nếu chưa có
    final storeUri = Uri.parse('https://play.google.com/store/apps/details?id=${bank.packageName}');
    if (await canLaunchUrl(storeUri)) {
      return await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }

    return false;
  }
}
