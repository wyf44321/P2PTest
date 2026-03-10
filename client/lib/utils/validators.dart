class Validators {
  Validators._();

  static final _ipv4Pattern = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );

  static String? validateIp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入 IP 地址';
    }
    if (!_ipv4Pattern.hasMatch(value.trim())) {
      return '请输入合法的 IP 地址';
    }
    return null;
  }

  static String? validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return '端口号须为 1-65535';
    }
    return null;
  }

  static String? validateStunAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入服务器地址';
    }
    return null;
  }

  static String? validateStunPort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口号';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      return '端口号须为 1-65535';
    }
    return null;
  }

  static ({String ip, int port})? parseIpPort(String value) {
    final trimmed = value.trim();
    final colonIndex = trimmed.lastIndexOf(':');
    if (colonIndex < 0) return null;
    final ip = trimmed.substring(0, colonIndex);
    final portStr = trimmed.substring(colonIndex + 1);
    if (!_ipv4Pattern.hasMatch(ip)) return null;
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) return null;
    return (ip: ip, port: port);
  }

  static bool isPrivateIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 127) return true;
    return false;
  }
}
