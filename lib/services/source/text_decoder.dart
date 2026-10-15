import 'package:novel_reader/core/text/byte_text_decoder.dart' as core;

/// 在线源响应体的解码。
///
/// 与本地书籍文件的关键区别：**编码是源声明里写死的**，不做回退猜测。
/// 站点声明 `gb18030` 就按 `gb18030` 解；猜出来的编码和站点声明不一致时，
/// 乱码比报错更难排查。
///
/// 实际解码逻辑统一在 [core.decodeWithCharset]，这里只保留
/// 「按声明编码解码」这一层语义与 `isKnownCharset` 的校验入口。
String decodeBytes(List<int> bytes, String charset) {
  return core.decodeWithCharset(bytes, charset);
}

/// 该编码名是否被支持（manifest 安装时校验用）。
bool isKnownCharset(String charset) => core.isKnownCharsetName(charset);
