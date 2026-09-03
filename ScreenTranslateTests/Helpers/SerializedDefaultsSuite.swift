import Testing

/// UserDefaults.standard를 읽고 쓰는 suite들의 부모.
/// Swift Testing은 서로 다른 suite를 병렬로 실행하므로, 같은 키(targetLanguageCode, popupFontName 등)를
/// 건드리는 suite끼리 경합해 간헐적으로 실패했다. `.serialized`는 중첩 suite에도 적용된다.
@Suite(.serialized)
enum SerializedDefaultsSuite {}
