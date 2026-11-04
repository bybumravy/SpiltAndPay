import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Đại diện cấu hình của một ứng dụng ngân hàng / ví điện tử được hỗ trợ.
class BankAppInfo {
  final String id;
  final String name;
  final String shortName;
  final String packageName;
  final String scheme;
  final List<String> altSchemes;
  final Color brandColor;
  final IconData icon;

  const BankAppInfo({
    required this.id,
    required this.name,
    required this.shortName,
    required this.packageName,
    required this.scheme,
    this.altSchemes = const [],
    required this.brandColor,
    this.icon = Icons.account_balance,
  });

  /// Danh sách tất cả các URI Scheme khả dĩ để thử kích hoạt app.
  List<String> get allSchemes => [scheme, ...altSchemes];
}

const List<BankAppInfo> kSupportedBanks = [
  BankAppInfo(
    id: 'mbbank',
    name: 'MBBank (Quân Đội)',
    shortName: 'MBBank',
    packageName: 'com.mbmobile',
    scheme: 'mbbank://',
    altSchemes: ['mbmobile://'],
    brandColor: Color(0xFF1E4399),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'vcb',
    name: 'Vietcombank (VCB Digibank)',
    shortName: 'Vietcombank',
    packageName: 'com.VCB',
    scheme: 'vietcombankmobile://',
    altSchemes: ['vcb://', 'vcbdigibank://'],
    brandColor: Color(0xFF005B27),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'techcombank',
    name: 'Techcombank Mobile',
    shortName: 'Techcombank',
    packageName: 'vn.com.techcombank.bb.app',
    scheme: 'tcb://',
    altSchemes: ['techcombank://'],
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
    altSchemes: ['bidv://', 'bidv.smartbanking.partner://'],
    brandColor: Color(0xFF0F75BC),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'tpbank',
    name: 'TPBank Mobile',
    shortName: 'TPBank',
    packageName: 'com.tpb.mb.gprsandroid',
    scheme: 'hydro://',
    altSchemes: ['tpbank://'],
    brandColor: Color(0xFF7B2082),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'vpbank',
    name: 'VPBank NEO',
    shortName: 'VPBank',
    packageName: 'com.vnpay.vpbankonline',
    scheme: 'vpbankneo://',
    altSchemes: ['vpbank://'],
    brandColor: Color(0xFF007E33),
    icon: Icons.account_balance,
  ),
  BankAppInfo(
    id: 'acb',
    name: 'ACB ONE',
    shortName: 'ACB',
    packageName: 'mobile.acb.com.vn',
    scheme: 'acbone://',
    altSchemes: ['acb://'],
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
    altSchemes: ['viettelmoney.vn://', 'vtpaystaging.vn://'],
    brandColor: Color(0xFFE60000),
    icon: Icons.account_balance_wallet,
  ),
];

class BankingAppService {
  /// Kiểm tra xem ứng dụng ngân hàng có mở được trên máy không.
  static Future<bool> isBankInstalled(BankAppInfo bank) async {
    for (final s in bank.allSchemes) {
      try {
        final uri = Uri.parse(s);
        if (await canLaunchUrl(uri)) return true;
      } catch (_) {}
    }
    return false;
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

  /// Mở ứng dụng ngân hàng được chọn (mã VietQR động đã tích hợp sẵn số tiền & nội dung).
  static Future<bool> openBankApp({
    required BankAppInfo bank,
    String? transferNote,
  }) async {
    // 1. Thử kích hoạt App Scheme (ưu tiên scheme chính, sau đó thử các alternative schemes)
    for (final s in bank.allSchemes) {
      try {
        final schemeUri = Uri.parse(s);
        if (await canLaunchUrl(schemeUri)) {
          final launched = await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
          if (launched) return true;
        }
      } catch (e) {
        debugPrint('Error launching scheme $s for ${bank.id}: $e');
      }
    }

    // 2. Fallback: Mở Google Play Store để cài đặt nếu máy chưa có ứng dụng
    final storeUri = Uri.parse('https://play.google.com/store/apps/details?id=${bank.packageName}');
    if (await canLaunchUrl(storeUri)) {
      return await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    }

    return false;
  }
}
