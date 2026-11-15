package io.github.slawa19.audiobook_reader

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Единственная звуковая дорожка собственного MediaMuxer, не редактор произвольных MP4. */
internal object M4aGapless {
    private data class Box(val start: Int, val size: Int, val type: String) {
        val end get() = start + size
    }

    private fun boxes(data: ByteArray, start: Int, end: Int): List<Box> {
        val result = mutableListOf<Box>()
        val view = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        var at = start
        while (at < end) {
            check(end - at >= 8) { "Оборванный заголовок M4A" }
            val size = view.getInt(at)
            check(size >= 8 && size <= end - at) { "Неверный размер блока M4A" }
            result.add(Box(at, size, String(data, at + 4, 4, Charsets.US_ASCII)))
            at += size
        }
        return result
    }

    private fun box(type: String, payload: ByteArray): ByteArray =
        ByteBuffer.allocate(payload.size + 8).order(ByteOrder.BIG_ENDIAN)
            .putInt(payload.size + 8).put(type.toByteArray(Charsets.US_ASCII)).put(payload).array()

    fun trim(file: File, samples: Long, sampleRate: Int, priming: Int) {
        require(priming >= 0)
        RandomAccessFile(file, "rw").use { target ->
            // Muxer может зарезервировать free/ перед mdat. moov переносим в конец,
            // старый объявляем free: ни один offset звуковых данных не меняется.
            var position = 0L
            var moovPosition = -1L
            var moov: ByteArray? = null
            while (position < target.length()) {
                target.seek(position)
                var size = target.readInt().toLong() and 0xffffffffL
                val type = ByteArray(4).also { target.readFully(it) }.toString(Charsets.US_ASCII)
                val header = if (size == 1L) 16 else 8
                if (size == 1L) size = target.readLong()
                if (size == 0L) size = target.length() - position
                check(size >= header && size <= target.length() - position) { "Неверный блок M4A" }
                if (type == "moov") {
                    check(moov == null && header == 8 && size <= Int.MAX_VALUE) { "Неверный moov" }
                    moovPosition = position
                    target.seek(position)
                    moov = ByteArray(size.toInt()).also { target.readFully(it) }
                }
                position += size
            }
            val data = checkNotNull(moov) { "В M4A нет moov" }
            val top = boxes(data, 8, data.size)
            val movie = top.single { it.type == "mvhd" }
            val track = top.single { it.type == "trak" }
            val children = boxes(data, track.start + 8, track.end)
            val trackHeader = children.single { it.type == "tkhd" }
            val media = children.single { it.type == "mdia" }
            val mediaHeader = boxes(data, media.start + 8, media.end).single { it.type == "mdhd" }
            val view = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
            fun timeScale(header: Box): Long {
                val offset = if (data[header.start + 8].toInt() == 1) 28 else 20
                return view.getInt(header.start + offset).toLong() and 0xffffffffL
            }
            val movieScale = timeScale(movie)
            val mediaScale = timeScale(mediaHeader)
            check(movieScale > 0 && mediaScale > 0) { "Неверная шкала времени M4A" }
            val duration = (samples * movieScale + sampleRate / 2) / sampleRate
            fun duration(header: Box, version0Offset: Int, version1Offset: Int) {
                if (data[header.start + 8].toInt() == 1) {
                    view.putLong(header.start + version1Offset, duration)
                } else {
                    check(duration <= 0xffffffffL) { "Слишком длинная дорожка M4A" }
                    view.putInt(header.start + version0Offset, duration.toInt())
                }
            }
            duration(movie, 24, 32)
            duration(trackHeader, 28, 36)
            val edit = box("edts", box("elst", ByteBuffer.allocate(28).order(ByteOrder.BIG_ENDIAN)
                .putInt(0x01000000).putInt(1).putLong(duration)
                .putLong((priming.toLong() * mediaScale + sampleRate / 2) / sampleRate)
                .putInt(0x00010000).array()))
            val trackPayload = children.filter { it.type != "edts" }
                .fold(ByteArray(0)) { result, child -> result + data.copyOfRange(child.start, child.end) } + edit
            val newTrack = box("trak", trackPayload)
            val newMoov = box("moov", top.fold(ByteArray(0)) { result, child ->
                result + if (child == track) newTrack else data.copyOfRange(child.start, child.end)
            })
            target.seek(moovPosition + 4)
            target.write("free".toByteArray(Charsets.US_ASCII))
            target.seek(target.length())
            target.write(newMoov)
            target.fd.sync()
        }
    }
}
