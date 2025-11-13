import 'dart:async';
import 'data_repository.dart';
import 'models.dart';

Future<void> main() async {
  final repository = DataRepository();

  print('🚀 Fetching users...');
  final users = await repository.fetchUsers();

  print('\n📋 All Users:');
  for (final user in users) {
    print(' - ${user.name} (${user.email})');
  }

  print('\n🔍 Searching for users with "Leanne" in the name...');
  final filtered = repository.filterUsersByName('Leanne');
  for (final user in filtered) {
    print('   👉 ${user.name}');
  }

  print('\n📦 Fetching posts by first user...');
  final posts = await repository.fetchPostsByUser(users.first.id);
  for (final post in posts.take(3)) {
    print('   📝 ${post.title}');
  }
}
