import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../services/storage_service.dart';

/// Repository for group CRUD operations
class GroupRepository {
  static const _uuid = Uuid();

  /// Create a new group
  Future<GroupModel> createGroup({
    required String name,
    String emoji = '🎵',
    String colorHex = '#7C4DFF',
  }) async {
    final group = GroupModel(
      id: _uuid.v4(),
      name: name,
      emoji: emoji,
      colorHex: colorHex,
    );
    await StorageService.groupsBox.put(group.id, group);
    return group;
  }

  /// Get all groups
  List<GroupModel> getAllGroups() {
    final groups = StorageService.groupsBox.values.toList();
    // Sort: smart groups first, then by creation date
    groups.sort((a, b) {
      if (a.isSmartGroup && !b.isSmartGroup) return -1;
      if (!a.isSmartGroup && b.isSmartGroup) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return groups;
  }

  /// Get a group by ID
  GroupModel? getGroup(String id) {
    return StorageService.groupsBox.get(id);
  }

  /// Update group details
  Future<void> updateGroup(GroupModel group) async {
    await StorageService.groupsBox.put(group.id, group);
  }

  /// Delete a group
  Future<void> deleteGroup(String id) async {
    // Don't allow deleting smart groups
    final group = StorageService.groupsBox.get(id);
    if (group != null && !group.isSmartGroup) {
      await StorageService.groupsBox.delete(id);
    }
  }

  /// Add a song to a group
  Future<void> addSongToGroup(String groupId, int songId) async {
    final group = StorageService.groupsBox.get(groupId);
    if (group != null) {
      group.addSong(songId);
      await group.save();
    }
  }

  /// Remove a song from a group
  Future<void> removeSongFromGroup(String groupId, int songId) async {
    final group = StorageService.groupsBox.get(groupId);
    if (group != null) {
      group.removeSong(songId);
      await group.save();
    }
  }
}
