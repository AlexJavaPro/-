package ru.amajo.photomailer.automation

object ShareBatchPlanner {
    fun splitByLimit(
        photos: List<ShareAutomationPhoto>,
        limitBytes: Long,
    ): List<ShareAutomationBatch> {
        if (photos.isEmpty()) {
            return emptyList()
        }
        val safeLimit = limitBytes.coerceAtLeast(1L)
        val sorted = photos
            .withIndex()
            .sortedWith(
                compareByDescending<IndexedValue<ShareAutomationPhoto>> { it.value.sizeBytes }
                    .thenBy { it.index },
            )

        val bins = mutableListOf<MutableList<ShareAutomationPhoto>>()
        val binSizes = mutableListOf<Long>()

        for (entry in sorted) {
            val item = entry.value
            if (item.sizeBytes > safeLimit) {
                bins += mutableListOf(item)
                binSizes += item.sizeBytes
                continue
            }

            var targetBin = -1
            for (index in bins.indices) {
                if (binSizes[index] + item.sizeBytes <= safeLimit) {
                    targetBin = index
                    break
                }
            }

            if (targetBin >= 0) {
                bins[targetBin] += item
                binSizes[targetBin] += item.sizeBytes
            } else {
                bins += mutableListOf(item)
                binSizes += item.sizeBytes
            }
        }

        return bins.mapIndexed { index, batchPhotos ->
            ShareAutomationBatch(
                index = index,
                photos = batchPhotos.toList(),
                totalBytes = batchPhotos.sumOf { it.sizeBytes },
            )
        }
    }
}

