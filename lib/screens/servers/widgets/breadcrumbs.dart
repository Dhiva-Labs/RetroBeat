import 'package:flutter/material.dart';

import '../../../providers/server_providers.dart';

/// One tappable segment of a [ServerBreadcrumbs] trail.
class _Crumb {
  const _Crumb(this.label, this.path);

  final String label;
  final String path;
}

/// Folder trail from a server's configured root down to the folder currently
/// open, so "how do I get back to Music" never requires backing out one level
/// at a time.
///
/// The trail always starts at [rootPath] rather than the server's real root
/// `/` — a server mounted at `/Music` has nothing useful above that for this
/// app to show.
class ServerBreadcrumbs extends StatelessWidget {
  const ServerBreadcrumbs({
    super.key,
    required this.rootPath,
    required this.currentPath,
    required this.onSelect,
  });

  final String rootPath;
  final String currentPath;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final crumbs = _crumbsFor(rootPath, currentPath);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: crumbs.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: scheme.outline,
        ),
        itemBuilder: (context, index) {
          final crumb = crumbs[index];
          final isCurrent = index == crumbs.length - 1;
          return Center(
            child: InkWell(
              key: ValueKey('crumb_${crumb.path}'),
              borderRadius: BorderRadius.circular(8),
              onTap: isCurrent ? null : () => onSelect(crumb.path),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  crumb.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? scheme.onSurface : scheme.primary,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<_Crumb> _crumbsFor(String rootPath, String currentPath) {
    final root = WebDavClient.normalizePath(rootPath);
    final current = WebDavClient.normalizePath(currentPath);
    final rootLabel = root == '/' ? 'Root' : WebDavClient.basename(root);
    final crumbs = [_Crumb(rootLabel, root)];
    if (current == root) return crumbs;

    final prefix = root == '/' ? '/' : '$root/';
    if (!current.startsWith(prefix)) {
      // Should not happen — every path handed in stays under the root — but
      // a stray path is not worth crashing the breadcrumb over.
      return crumbs;
    }

    var accumulated = root;
    for (final segment in current.substring(prefix.length).split('/')) {
      if (segment.isEmpty) continue;
      accumulated = WebDavClient.joinPath(accumulated, segment);
      crumbs.add(_Crumb(segment, accumulated));
    }
    return crumbs;
  }
}
