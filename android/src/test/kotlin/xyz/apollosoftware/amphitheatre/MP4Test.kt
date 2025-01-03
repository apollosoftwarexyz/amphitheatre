package xyz.apollosoftware.amphitheatre

import org.junit.jupiter.api.Test
import kotlin.math.pow
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

class MP4Test {

    @Test
    fun testByteArrayToInt() {
        assertEquals(0, byteArrayOf(0, 0, 0, 0).toInt())
        assertEquals(256.0.pow(0).toInt(), byteArrayOf(0, 0, 0, 1).toInt())
        assertEquals(256.0.pow(1).toInt(), byteArrayOf(0, 0, 1, 0).toInt())
        assertEquals(256.0.pow(2).toInt(), byteArrayOf(0, 1, 0, 0).toInt())
        assertEquals(256.0.pow(3).toInt(), byteArrayOf(1, 0, 0, 0).toInt())

        assertContentEquals("ftyp".toByteArray(), byteArrayOf(102, 116, 121, 112))
        assertEquals(1718909296, byteArrayOf(102, 116, 121, 112).toInt())

        assertEquals(
            1.shl(24)
                .or(2.shl(16))
                .or(3.shl(8))
                .or(4),
            byteArrayOf(1, 2, 3, 4).toInt()
        )

        assertEquals(
            255.shl(24)
                .or(2.shl(16))
                .or(255.shl(8))
                .or(4),
            byteArrayOf(-1, 2, -1, 4).toInt()
        )

        assertEquals(
            1.shl(24)
                .or(255.shl(16))
                .or(3.shl(8))
                .or(255),
            byteArrayOf(1, -1, 3, -1).toInt()
        )

        assertEquals(
            255.shl(24)
                .or(255.shl(16))
                .or(255.shl(8))
                .or(255),
            byteArrayOf(-1, -1, -1, -1).toInt()
        )

        assertEquals(
            -1,
            byteArrayOf(-1, -1, -1, -1).toInt()
        )
    }

    @Test
    fun testByteArrayToLong() {
        assertEquals(0, byteArrayOf(0, 0, 0, 0, 0, 0, 0, 0).toLong())
        assertEquals(256.0.pow(0.0).toLong(), byteArrayOf(0, 0, 0, 0, 0, 0, 0, 1).toLong())
        assertEquals(256.0.pow(1.0).toLong(), byteArrayOf(0, 0, 0, 0, 0, 0, 1, 0).toLong())
        assertEquals(256.0.pow(2.0).toLong(), byteArrayOf(0, 0, 0, 0, 0, 1, 0, 0).toLong())
        assertEquals(256.0.pow(3.0).toLong(), byteArrayOf(0, 0, 0, 0, 1, 0, 0, 0).toLong())
        assertEquals(256.0.pow(4.0).toLong(), byteArrayOf(0, 0, 0, 1, 0, 0, 0, 0).toLong())
        assertEquals(256.0.pow(5.0).toLong(), byteArrayOf(0, 0, 1, 0, 0, 0, 0, 0).toLong())
        assertEquals(256.0.pow(6.0).toLong(), byteArrayOf(0, 1, 0, 0, 0, 0, 0, 0).toLong())
        assertEquals(256.0.pow(7.0).toLong(), byteArrayOf(1, 0, 0, 0, 0, 0, 0, 0).toLong())

        assertContentEquals("ftypftyp".toByteArray(), byteArrayOf(102, 116, 121, 112, 102, 116, 121, 112))
        assertEquals(1718909296, byteArrayOf(0, 0, 0, 0, 102, 116, 121, 112).toLong())

        assertEquals(
            1L.shl(24)
                .or(2.shl(16))
                .or(3.shl(8))
                .or(4),
            byteArrayOf(0, 0, 0, 0, 1, 2, 3, 4).toLong()
        )

        assertEquals(
            255L.shl(24)
                .or(2.shl(16))
                .or(255.shl(8))
                .or(4),
            byteArrayOf(0, 0, 0, 0, -1, 2, -1, 4).toLong()
        )

        assertEquals(
            1L.shl(24)
                .or(255.shl(16))
                .or(3.shl(8))
                .or(255),
            byteArrayOf(0, 0, 0, 0, 1, -1, 3, -1).toLong()
        )

        assertEquals(
            255L.shl(24)
                .or(255.shl(16))
                .or(255.shl(8))
                .or(255),
            byteArrayOf(0, 0, 0, 0, -1, -1, -1, -1).toLong()
        )

        assertEquals(
            -1,
            byteArrayOf(-1, -1, -1, -1, -1, -1, -1, -1).toLong()
        )
    }

}