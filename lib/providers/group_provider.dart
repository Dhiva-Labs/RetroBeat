import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/group_model.dart';
import '../data/repositories/group_repository.dart';

/// Provider for GroupRepository
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository();
});

/// Provider for all groups
final groupsProvider =
    StateNotifierProvider<GroupsNotifier, List<GroupModel>>((ref) {
  return GroupsNotifier(ref.watch(groupRepositoryProvider));
});

class GroupsNotifier extends StateNotifier<List<GroupModel>> {
  final GroupRepository _repository;

  GroupsNotifier(this._repository) : super([]) {
    loadGroups();
  }

  void loadGroups() {
    state = _repository.getAllGroups();
  }

  Future<GroupModel> createGroup({
    required String name,
    String emoji = '🎵',
    String colorHex = '#7C4DFF',
  }) async {
    final group = await _repository.createGroup(
      name: name,
      emoji: emoji,
      colorHex: colorHex,
    );
    state = _repository.getAllGroups();
    return group;
  }

  Future<void> deleteGroup(String id) async {
    await _repository.deleteGroup(id);
    state = _repository.getAllGroups();
  }

  Future<void> updateGroup(GroupModel group) async {
    await _repository.updateGroup(group);
    state = _repository.getAllGroups();
  }

  Future<void> addSongToGroup(String groupId, int songId) async {
    await _repository.addSongToGroup(groupId, songId);
    state = _repository.getAllGroups();
  }

  Future<void> removeSongFromGroup(String groupId, int songId) async {
    await _repository.removeSongFromGroup(groupId, songId);
    state = _repository.getAllGroups();
  }
}
