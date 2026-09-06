import 'package:flutter/material.dart';

class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('contact'),
    body: Center(child: Text(userId)),
  );
}
