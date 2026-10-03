import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum UserRole { admin, user }

class RoleProvider extends ChangeNotifier {
  UserRole _role = UserRole.user;
  bool _isLoading = true;

  UserRole get role => _role;
  bool get isAdmin => _role == UserRole.admin;
  bool get isLoading => _isLoading;

  Future<void> loadRole() async {
    _isLoading = true;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _role = UserRole.user;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final roleStr = doc.data()?['role'] as String? ?? 'user';
      _role = roleStr == 'admin' ? UserRole.admin : UserRole.user;
    } catch (e) {
      _role = UserRole.user; 
    }

    _isLoading = false;
    notifyListeners();
  }

  void reset() {
    _role = UserRole.user;
    notifyListeners();
  }
}

class AdminOnly extends StatelessWidget {
  final Widget child;
  final Widget? fallback;
  const AdminOnly({super.key, required this.child, this.fallback});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<RoleProvider>().isAdmin;
    if (isAdmin) return child;
    return fallback ?? const SizedBox.shrink();
  }
}