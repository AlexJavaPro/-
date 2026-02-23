List<List<int>> splitSizesByLimit(
  List<int> sizesBytes,
  int limitBytes,
) {
  if (limitBytes <= 0) {
    throw ArgumentError.value(limitBytes, 'limitBytes', 'Must be greater than 0');
  }
  final groups = <List<int>>[];
  var currentGroup = <int>[];
  var currentSize = 0;

  for (final size in sizesBytes) {
    if (size > limitBytes) {
      if (currentGroup.isNotEmpty) {
        groups.add(currentGroup);
        currentGroup = <int>[];
        currentSize = 0;
      }
      groups.add(<int>[size]);
      continue;
    }

    if (currentGroup.isNotEmpty && currentSize + size > limitBytes) {
      groups.add(currentGroup);
      currentGroup = <int>[];
      currentSize = 0;
    }

    currentGroup.add(size);
    currentSize += size;
  }

  if (currentGroup.isNotEmpty) {
    groups.add(currentGroup);
  }

  return groups;
}

