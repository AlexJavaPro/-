package ru.amajo.photomailer

import org.junit.Assert.assertEquals
import org.junit.Test
import ru.amajo.photomailer.split.BatchSplitter

class BatchSplitterTest {
    @Test
    fun `split into one batch when total under limit`() {
        val sizes = listOf(5L, 7L, 8L)
        val groups = BatchSplitter.split(sizes, 30L) { it }
        assertEquals(1, groups.size)
    }

    @Test
    fun `oversized item creates standalone batch`() {
        val sizes = listOf(5L, 50L, 6L)
        val groups = BatchSplitter.split(sizes, 20L) { it }
        assertEquals(3, groups.size)
        assertEquals(listOf(50L), groups[1])
    }
}

