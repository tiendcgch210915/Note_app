import 'package:flutter/material.dart';

/// Navigator key ở cấp root — dùng cho các widget sống ngoài cây Navigator
/// (ví dụ banner global trong `MaterialApp.builder`) cần tự điều hướng mà
/// không có BuildContext nằm trong Navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
