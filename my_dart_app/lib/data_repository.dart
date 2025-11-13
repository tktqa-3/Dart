import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class DataRepository {
  List<User> _cachedUsers = [];

  Future<List<User>> fetchUsers() async {
    if (_cachedUsers.isNotEmpty) return _cachedUsers;

    final response = await http.get(
      Uri.parse('https://jsonplaceholder.typicode.com/users'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch users: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as List;
    _cachedUsers = data.map((json) => User.fromJson(json)).toList();
    return _cachedUsers;
  }

  List<User> filterUsersByName(String keyword) {
    return _cachedUsers
        .where((u) => u.name.toLowerCase().contains(keyword.toLowerCase()))
        .toList();
  }

  Future<List<Post>> fetchPostsByUser(int userId) async {
    final response = await http.get(
      Uri.parse('https://jsonplaceholder.typicode.com/posts?userId=$userId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch posts: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as List;
    return data.map((json) => Post.fromJson(json)).toList();
  }
}
