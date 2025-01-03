package xyz.apollosoftware.amphitheatre

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder.BIG_ENDIAN
import java.util.*
import kotlin.collections.ArrayList

/**
 * Converts the [ByteArray] to an [Int].
 *
 * The bytes are converted in big-endian/network order.
 * That is, the first byte will be shifted 24 bits to the left, the next byte 16 to the left, and so on.
 */
fun ByteArray.toInt(): Int {
    if (size != 4) {
        throw IllegalArgumentException("Cannot convert ByteArray to 32-bit integer where its size is not equal to 4")
    }

    return ByteBuffer.wrap(this).order(BIG_ENDIAN).getInt()
}

/**
 * Converts the [ByteArray] to an [Long].
 *
 * The bytes are converted in big-endian/network order.
 * That is, the first byte will be shifted 56 bits to the left, the next byte 48 to the left, and so on.
 */
fun ByteArray.toLong(): Long {
    if (size != 8) {
        throw IllegalArgumentException("Cannot convert ByteArray to 64-bit integer where its size is not equal to 8")
    }

    return ByteBuffer.wrap(this).order(BIG_ENDIAN).getLong()
}

fun Int.toByteArray(): ByteArray = ByteBuffer.allocate(4).order(BIG_ENDIAN).putInt(this).array()
fun Int.toCharacterString(): String = String(toByteArray())
fun Long.toByteArray(): ByteArray = ByteBuffer.allocate(8).order(BIG_ENDIAN).putLong(this).array()

fun InputStream.next(n: Int): ByteArray {
    val byteArray = ByteArray(n)
    read(byteArray)
    return byteArray
}

/** Drain the [InputStream] into a [ByteArray]. */
fun InputStream.drain(): ByteArray = ByteArrayOutputStream().use { outputStream ->
    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
    var n = 0

    do {
        n = read(buffer, 0, DEFAULT_BUFFER_SIZE)
        if (n > 0) outputStream.write(buffer, 0, n)
    } while (n >= 0)

    outputStream.flush()
    return outputStream.toByteArray()
}

typealias BoxConstructor = (rawSize: Int, size: Long, type: Int, data: ByteArray) -> Box

enum class BoxType(val bytes: ByteArray,
                   val rawType: Int = bytes.toInt(),
                   val creator: BoxConstructor = { rawSize, size, type, data -> Box(rawSize, size, type, data) }) {
    /** File type box ("ftyp"). */
    FTYP(bytes = "ftyp".toByteArray(), creator = { rawSize, size, type, data -> FileTypeBox(rawSize, size, type, data) }),

    /** Progress Download Information box ("pdin"). */
    PDIN(bytes = "pdin".toByteArray()),

    /** Movie box ("moov"). */
    MOOV(bytes = "moov".toByteArray(), creator = { rawSize, size, type, data -> MovieBox(rawSize, size, type, data) }),

    /** Movie data box ("mdat"). */
    MDAT(bytes = "mdat".toByteArray()),

    /** Track box ("trak"). */
    TRAK(bytes = "trak".toByteArray(), creator = { rawSize, size, type, data -> TrackBox(rawSize, size, type, data) }),

    /** Media header box ("mdia"). */
    MDIA(bytes = "mdia".toByteArray(), creator = { rawSize, size, type, data -> MediaBox(rawSize, size, type, data) }),

    /** Media information header ("minf"). */
    MINF(bytes = "minf".toByteArray(), creator = { rawSize, size, type, data -> MediaInfoBox(rawSize, size, type, data) }),

    /** Sample table box ("stbl"). */
    STBL(bytes = "stbl".toByteArray(), creator = { rawSize, size, type, data -> SampleTableBox(rawSize, size, type, data) }),

    /** 32-bit chunk offset box - Sample Table Chunk Offset ("stco"). */
    STCO(bytes = "stco".toByteArray(), creator = { rawSize, size, type, data -> ChunkOffset32Box(rawSize, size, type, data) }),

    /** 64-bit chunk offset box - Chunk Offset 64-bit ("co64"). */
    CO64(bytes = "co64".toByteArray(), creator = { rawSize, size, type, data -> ChunkOffset64Box(rawSize, size, type, data) }),

    /** Free space ("free"). */
    FREE(bytes = "free".toByteArray());

    fun equalsRawType(rawType: Int): Boolean = this.rawType == rawType

    override fun toString(): String = rawType.toCharacterString()

    companion object {
        /**
         * Get the [BoxType] for a given [rawType].
         */
        fun getByRawType(rawType: Int): BoxType? = values().find { it.equalsRawType(rawType) }
    }
}

/** An MPEG-4 Box (also referred to as an 'atom') */
open class Box(
    /**
     * The raw size of the entire [Box] as it appeared in the file.
     */
    val rawSize: Int,
    /**
     * The size of the entire [Box], *including* headers, rather than just the content.
     *
     * Use `data.size` ([ByteArray.size]) to get the size of the content alone.
     */
    val size: Long,
    /** The type of the [Box]. */
    internal val type: Int,
    /** The raw content of the [Box]. */
    internal val data: ByteArray,
) {

    /** Check if the type of the [Box] matches the specified [BoxType]. */
    fun isType(boxType: BoxType) = boxType.equalsRawType(type)

    /** Write the [Box] into the [stream]. Calls [writeData] to write the contents of the [Box]. */
    open fun write(stream: OutputStream) {
        stream.write(rawSize.toByteArray())
        stream.write(type.toByteArray())
        if (rawSize == 1) stream.write(size.toByteArray())
        writeData(stream)
        stream.flush()
    }

    /** Writes the contents of the [Box]. See [write]. */
    protected open fun writeData(stream: OutputStream) = stream.write(data)

    override fun toString(): String
            = "$rawSize (${size}) - $type (${BoxType.getByRawType(type) ?: "unknown - ${type.toCharacterString()}"})"

    companion object {

        /**
         * Read the next box from the [InputStream].
         */
        fun readFrom(inputStream: InputStream): Box {
            val rawSize = inputStream.next(4).toInt()
            val type = inputStream.next(4).toInt()

            val (size: Long, data: ByteArray) = when (rawSize) {
                0 -> {
                    val data = inputStream.drain()
                    Pair(data.size.toLong(), data)
                }
                1 -> {
                    // Use the 'largesize' instead.
                    val size = inputStream.next(8).toLong()

                    if (size > Int.MAX_VALUE) {
                        throw UnsupportedOperationException("Cannot read more than ${Int.MAX_VALUE} bytes, but the '$type' atom is $size bytes.")
                    }

                    Pair(
                        size,
                        inputStream.next(size.toInt() - 16 /* minus the header (size + type + 'largesize') */)
                    )
                }
                else -> {
                    Pair(
                        rawSize.toLong(),
                        inputStream.next(rawSize - 8 /* minus the header (size + type) */)
                    )
                }
            }

            val supportedType = BoxType.getByRawType(type)
            val factory: BoxConstructor = supportedType?.creator ?: { boxRawSize, boxSize, boxType, boxData -> Box(boxRawSize, boxSize, boxType, boxData) }
            return factory(rawSize, size, type, data)
        }

    }

}

open class FullBox(rawSize: Int, size: Long, type: Int, data: ByteArray): Box(rawSize, size, type, data) {

    /** The version of this format of the [FullBox]. */
    val version: Byte by lazy { data[0] }

    /** The three bytes of flags at the start of the [FullBox]. */
    val flags: ByteArray by lazy { data.copyOfRange(1, 4) }

    override fun writeData(stream: OutputStream) {
        stream.write(version.toInt())
        stream.write(flags)
        writeFullBoxData(stream)
    }

    /** Write the data past the [FullBox] header (i.e., after [version] and [flags]). */
    protected open fun writeFullBoxData(stream: OutputStream)
            = stream.write(data.copyOfRange(4, data.size))

}

class FileTypeBox(rawSize: Int, size: Long, type: Int, data: ByteArray): Box(rawSize, size, type, data) {

    /** The specification which is the 'best use' of the file, per the MPEG-4 specification. */
    val majorBrand: Int by lazy { data.copyOfRange(0, 4).toInt() }

    /** The full list of brands that the file is marked as being compatible with. It should include [majorBrand]. */
    val compatibleBrands: Set<Int> by lazy {
        data.copyOfRange(8, data.size).mapIndexed { index: Int, _ ->
            val i = index + 8

            if (i.mod(4) == 0) {
                byteArrayOf(data[i], data[i+1], data[i+2], data[i+3]).toInt()
            } else {
                null
            }
        }.filterNotNull().toSet()
    }

    fun isCompatibleWithAnyOf(brands: Set<Int>): Boolean = brands.any { compatibleBrands.contains(it) }

}

open class RecursiveBox(rawSize: Int, size: Long, type: Int, data: ByteArray): Box(rawSize, size, type, data) {

    val children: LinkedList<Box> by lazy { readChildren() }

    override fun write(stream: OutputStream) {
        // Collect the data from the children.
        val collector = ByteArrayOutputStream()
        children.forEach { it.write(collector) }
        val collectedData = collector.also { it.flush() }.toByteArray()

        // Write an amended header.
        if (rawSize == 1) stream.write(1.toByteArray()) else stream.write((collectedData.size + 8).toByteArray())
        stream.write(type.toByteArray())
        if (rawSize == 1) stream.write((collectedData.size.toLong() + 16).toByteArray())

        // Flush the collected data.
        stream.write(collectedData)
        stream.flush()
    }

    private fun readChildren(): LinkedList<Box> {
        val boxes: LinkedList<Box> = LinkedList()

        ByteArrayInputStream(data).use { stream ->
            while (stream.available() > 0) {
                boxes.add(readFrom(stream))
            }
        }

        return boxes
    }

    @Suppress("UNCHECKED_CAST")
    protected fun <T: Box> childrenByType(type: BoxType): Iterable<T> {
        return children.filter { it.isType(type) }.map { it as T }
    }

}

class MovieBox(rawSize: Int, size: Long, type: Int, data: ByteArray): RecursiveBox(rawSize, size, type, data) {

    val tracks: Iterable<TrackBox> by lazy { childrenByType(BoxType.TRAK) }

}

class TrackBox(rawSize: Int, size: Long, type: Int, data: ByteArray): RecursiveBox(rawSize, size, type, data) {

    val media: MediaBox by lazy { childrenByType<MediaBox>(BoxType.MDIA).first() }

}

class MediaBox(rawSize: Int, size: Long, type: Int, data: ByteArray): RecursiveBox(rawSize, size, type, data) {

    val info: MediaInfoBox by lazy { childrenByType<MediaInfoBox>(BoxType.MINF).first() }

}

class MediaInfoBox(rawSize: Int, size: Long, type: Int, data: ByteArray): RecursiveBox(rawSize, size, type, data) {

    val sampleTable: SampleTableBox by lazy { childrenByType<SampleTableBox>(BoxType.STBL).first() }

}

class SampleTableBox(rawSize: Int, size: Long, type: Int, data: ByteArray): RecursiveBox(rawSize, size, type, data) {

    val offset: ChunkOffsetBox<*> by lazy {
        children.find { it.isType(BoxType.STCO) or it.isType(BoxType.CO64) }!! as ChunkOffsetBox<*>
    }

}

abstract class ChunkOffsetBox<T: Number>(rawSize: Int, size: Long, type: Int, data: ByteArray): FullBox(rawSize, size, type, data) {

    /** Whether the [ChunkOffsetBox] is the 64-bit variant. */
    abstract val isLarge: Boolean

    /** The number of offsets in the box. */
    val count: Int by lazy { data.copyOfRange(4, 8).toInt() }

    /** The list of offsets in the box. */
    val items: ArrayList<T> by lazy { loadItems() }

    /** Load the list of [items]. This function is called lazily when [items] is accessed. */
    protected abstract fun loadItems(): ArrayList<T>

    /** Encode the [item] into a [ByteArray]. */
    protected abstract fun encodeItem(item: T): ByteArray

    override fun writeFullBoxData(stream: OutputStream) {
        stream.write(count.toByteArray())
        items.forEach { stream.write(encodeItem(it)) }
    }

    /**
     * Applies the specified [offset] to each of the [items].
     *
     * If the [offset] makes the new value too large for the type of [ChunkOffsetBox],
     * an [ArithmeticException] is thrown.
     */
    abstract fun addGlobalOffset(offset: Long)

}

class ChunkOffset32Box(rawSize: Int, size: Long, type: Int, data: ByteArray): ChunkOffsetBox<Int>(rawSize, size, type, data) {

    override val isLarge: Boolean = false

    override fun loadItems(): ArrayList<Int> {
        val items = ArrayList<Int>()
        for (i in 0 until count) { items.add(data.copyOfRange((i*4) + 8, (i*4) + 12).toInt()) }
        return items
    }

    override fun encodeItem(item: Int): ByteArray = item.toByteArray()

    override fun addGlobalOffset(offset: Long) {
        for (i in 0 until count) {
            val newValue = items[i] + offset
            if (newValue > Int.MAX_VALUE) {
                throw ArithmeticException("Offset cannot be applied to value. The result exceeds Int.MAX_VALUE.")
            }

            items[i] = newValue.toInt()
        }
    }

}

class ChunkOffset64Box(rawSize: Int, size: Long, type: Int, data: ByteArray): ChunkOffsetBox<Long>(rawSize, size, type, data) {

    override val isLarge: Boolean = true

    override fun loadItems(): ArrayList<Long> {
        val items = ArrayList<Long>()
        for (i in 0 until count) { items.add(data.copyOfRange((i*8) + 8, (i*8) + 16).toLong()) }
        return items
    }

    override fun encodeItem(item: Long): ByteArray = item.toByteArray()

    override fun addGlobalOffset(offset: Long) {
        for (i in 0 until count) {
            items[i] += offset
        }
    }

}

/**
 * Represents an MPEG-4 file.
 */
class MP4(private val inputStream: InputStream): AutoCloseable {

    /** Returns true if the file has a brand that is known to be compatible with this library. */
    val hasCompatibleBrand: Boolean by lazy {
        boxes.any {
            it is FileTypeBox && it.isCompatibleWithAnyOf(compatibleBrands)
        }
    }

    /**
     * True when the file [hasCompatibleBrand] but [isStreamable] is false.
     */
    val canBeMadeStreamable: Boolean
        get() = hasCompatibleBrand and !isStreamable

    /**
     * True when the file is considered 'streamable' (also known as 'fast start' - e.g., in FFmpeg).
     *
     * This is considered to be true when the [BoxType.MOOV] [Box] precedes the [BoxType.MDAT] box.
     *
     * The [BoxType.MOOV] box is essentially the 'table of contents' of the file, containing
     * relevant offsets that can be cached in memory whilst the file is played.
     *
     * If it is located after all the movie data, it cannot be cached because the whole file has to
     * be downloaded to locate the movie data, thus preventing streaming/'fast start'.
     *
     * You can use [makeStreamable] to convert a compatible file where [isStreamable] is false.
     */
    val isStreamable: Boolean
        get() = boxes.indexOfFirst { it.isType(BoxType.MOOV) } < boxes.indexOfFirst { it.isType(BoxType.MDAT) }

    private val boxes: LinkedList<Box> = LinkedList()

    init { while (inputStream.available() > 0) boxes.add(Box.readFrom(inputStream)) }

    /**
     * Make the [MP4] file streamable (such that [isStreamable] returns true).
     */
    fun makeStreamable(outputFile: File) {
        // Isolate the MovieBox so we can get its size.
        val movieBox: MovieBox = boxes.last() as MovieBox

        // Amend the offsets to factor in the size of the movieBox.
        movieBox.tracks.forEach {
            it.media.info.sampleTable.offset.addGlobalOffset(movieBox.size)
        }

        // Re-order the boxes.
        boxes.sortByDescending { it.isType(BoxType.FTYP) || it.isType(BoxType.MOOV) }

        outputFile.createNewFile()
        outputFile.outputStream().use { outputStream ->
            boxes.forEach { it.write(outputStream) }
        }
    }

    override fun close() = inputStream.close()

    companion object {
        /** The list of MPEG-4 brands that the [MP4] class is compatible with. */
        val compatibleBrands: Set<Int> = Collections.unmodifiableSet(setOf(
            "mp42".toByteArray().toInt(),
            "isom".toByteArray().toInt(),
        ))
    }

}
