import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lifeos_top_toast.dart';

abstract final class LifeOsLegalPolicyUrls {
  static const String privacyPolicyUrl =
      'https://life-os-vn-2026.web.app/privacy-policy.html';
  static const String accountDeletionUrl =
      'https://life-os-vn-2026.web.app/delete-account.html';
  static const String supportEmail = 'support@lifeos.vn';
}

Future<void> showLifeOsPrivacyPolicyDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        key: const Key('lifeos_privacy_policy_dialog'),
        title: const Text('Chính sách Quyền riêng tư & Điều khoản LifeOS'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Đơn vị phát triển: LifeOS Super App (vn.lifeos.app.life_os)\n'
                'Liên hệ hỗ trợ & bảo vệ dữ liệu: support@lifeos.vn\n'
                'Trang công khai (HTML): https://life-os-vn-2026.web.app/privacy-policy.html',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              const Text(
                '1. Dữ liệu thu thập & Mục đích sử dụng',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Tài khoản (Họ tên, Email, UID, Số điện thoại tùy chọn): Xác thực người dùng và đồng bộ dữ liệu đa thiết bị qua Firebase Authentication.\n'
                '• Sổ thu chi, ví, lịch hẹn & tài liệu gia đình: Lưu trữ mã hóa cục bộ và đồng bộ lên Google Cloud Firestore theo đúng phân quyền tài khoản hoặc nhóm gia đình.\n'
                '• Thông báo Ngân hàng & Ví điện tử (Tùy chọn, cần đồng ý riêng): Khi bạn chủ động bật, LifeOS chỉ đọc tiêu đề và nội dung biến động số dư từ ứng dụng Ngân hàng/Ví điện tử bạn chọn (tuyệt đối KHÔNG đọc ứng dụng Tin nhắn SMS). Mọi thông báo chứa mã OTP đều bị hủy ngay trên thiết bị và số thẻ được tự động che.\n'
                '• Giọng nói & Trợ lý AI (Tùy chọn): Nhận diện giọng nói tiếng Việt trực tiếp trên máy (Offline ASR) khi bạn bấm nút Micro. Chỉ gửi văn bản/số liệu tóm tắt tới Google Gemini khi bạn chủ động bật và nhập khóa kết nối theo tài khoản của mình.',
                style: TextStyle(fontSize: 12.5, height: 1.38),
              ),
              const SizedBox(height: 10),
              const Text(
                '2. Bên nhận dữ liệu & Biện pháp bảo vệ',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Toàn bộ dữ liệu được mã hóa khi truyền tải (HTTPS/TLS 1.3) và lưu trữ cục bộ bằng Android Keystore AES-256-GCM.\n'
                '• LifeOS chỉ sử dụng hạ tầng Google Firebase (Auth, Firestore, Cloud Functions) làm đơn vị xử lý dữ liệu; không bán dữ liệu cá nhân và không chia sẻ cho mạng quảng cáo bên thứ ba.\n'
                '• Mã QR chuyển khoản VietQR được dựng trực tiếp trên thiết bị từ chuỗi chuẩn EMVCo, không gửi số tài khoản hay số tiền ra dịch vụ tạo ảnh bên ngoài.',
                style: TextStyle(fontSize: 12.5, height: 1.38),
              ),
              const SizedBox(height: 10),
              const Text(
                '3. Thời gian lưu trữ & Quyền xóa dữ liệu (Trong App & Trên Web)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Dữ liệu chỉ được lưu trong thời gian tài khoản còn hoạt động.\n'
                '• Bạn có thể xóa vĩnh viễn tài khoản và toàn bộ dữ liệu máy chủ ngay trong mục Hồ sơ & Bảo mật Tài khoản → Xóa tài khoản.\n'
                '• Nếu đã gỡ ứng dụng, bạn có thể gửi yêu cầu xóa tài khoản trực tuyến tại trang Web công khai: https://life-os-vn-2026.web.app/delete-account.html (xử lý hoàn tất tối đa trong 7 ngày làm việc).',
                style: TextStyle(fontSize: 12.5, height: 1.38),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('copy_privacy_policy_url_button'),
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(
                          text: LifeOsLegalPolicyUrls.privacyPolicyUrl,
                        ),
                      );
                      if (dialogCtx.mounted) {
                        LifeOsTopToast.show(
                          dialogCtx,
                          'Đã sao chép URL Chính sách quyền riêng tư công khai.',
                        );
                      }
                    },
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('Sao chép URL Chính sách'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('copy_account_deletion_url_button'),
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(
                          text: LifeOsLegalPolicyUrls.accountDeletionUrl,
                        ),
                      );
                      if (dialogCtx.mounted) {
                        LifeOsTopToast.show(
                          dialogCtx,
                          'Đã sao chép URL Yêu cầu xóa tài khoản trên Web.',
                        );
                      }
                    },
                    icon: const Icon(Icons.delete_forever_outlined, size: 16),
                    label: const Text('Sao chép URL Xóa TK Web'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('close_privacy_policy_dialog_button'),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Đã hiểu & Đóng'),
          ),
        ],
      );
    },
  );
}
