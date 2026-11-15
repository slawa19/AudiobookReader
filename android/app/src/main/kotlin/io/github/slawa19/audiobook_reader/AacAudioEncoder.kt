package io.github.slawa19.audiobook_reader

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

/** Системный программный AAC-LC: одинаковый профиль и известная задержка на разных телефонах. */
object AacAudioEncoder {
    // Моно 24 кГц, речь: 48 кбит/с оставляют запас качества, занимая около 22 МБ/час.
    // Значение входит в Dart formatId; после изменения меняются и отпечатки.
    const val SPEECH_BIT_RATE = 48_000
    private const val FRAME_SAMPLES = 1024
    // FDK AAC-LC: DELAY_AAC(1024) = 1024 + 4*128 + 128/2 = 1600.
    // Используем именно c2.android.aac.encoder, не переносим эту константу на vendor-кодеки.
    // AOSP external/aac/libAACenc/src/aacenc_lib.cpp: DELAY_AAC, BSLA; nDelayCore.
    private const val PRIMING_SAMPLES = 1600
    private const val WAIT_US = 10_000L
    // Отсутствие продвижения — ошибка кодека, а не бесконечное ожидание очереди.
    private const val STALL_MS = 30_000L

    fun encode(pcmPath: String, outputPath: String, sampleRate: Int) {
        val input = File(pcmPath)
        val output = File(outputPath)
        require(input.canonicalPath != output.canonicalPath) { "Вход и выход совпадают" }
        var codec: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var complete = false
        try {
            val bytes = input.length()
            require(input.isFile && bytes > 0 && bytes % 2 == 0L && sampleRate > 0) {
                "Ожидается непустой PCM 16 бит моно с положительной частотой"
            }
            val samples = bytes / 2
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, SPEECH_BIT_RATE)
                setInteger(MediaFormat.KEY_PCM_ENCODING, android.media.AudioFormat.ENCODING_PCM_16BIT)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAME_SAMPLES * 2)
            }
            val encoder = MediaCodec.createByCodecName("c2.android.aac.encoder")
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val writer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            encoder.start()
            var track = -1
            var submitted = 0L
            var inputEnded = false
            var outputEnded = false
            var frames = 0L
            var lastProgress = SystemClock.elapsedRealtime()
            var priming = PRIMING_SAMPLES
            val info = MediaCodec.BufferInfo()
            val chunk = ByteArray(FRAME_SAMPLES * 2)
            input.inputStream().use { source ->
                while (!outputEnded) {
                    if (SystemClock.elapsedRealtime() - lastProgress > STALL_MS) {
                        throw IOException("Кодировщик AAC не отвечает")
                    }
                    if (!inputEnded) {
                        val index = encoder.dequeueInputBuffer(WAIT_US)
                        if (index >= 0) {
                            val buffer = checkNotNull(encoder.getInputBuffer(index))
                            buffer.clear()
                            val count = minOf(chunk.size.toLong(), bytes - submitted, buffer.remaining().toLong()).toInt()
                            require(count % 2 == 0) { "Нечётный размер буфера PCM" }
                            var read = 0
                            while (read < count) {
                                val n = source.read(chunk, read, count - read)
                                if (n < 0) throw IOException("PCM закончился раньше ожидаемого")
                                read += n
                            }
                            buffer.put(chunk, 0, count)
                            inputEnded = count == 0
                            // Время из числа отсчётов, без накопления ошибки округления.
                            encoder.queueInputBuffer(index, 0, count, submitted / 2 * 1_000_000 / sampleRate,
                                if (inputEnded) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                            submitted += count
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                    }
                    when (val index = encoder.dequeueOutputBuffer(info, WAIT_US)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            check(track == -1) { "Повторная смена формата AAC" }
                            val encodedFormat = encoder.outputFormat
                            if (encodedFormat.containsKey(MediaFormat.KEY_ENCODER_DELAY)) {
                                priming = encodedFormat.getInteger(MediaFormat.KEY_ENCODER_DELAY)
                            }
                            track = writer.addTrack(encodedFormat)
                            writer.start()
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                        else -> if (index >= 0) {
                            val ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            try {
                                val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                                if (!config && info.size > 0) {
                                    check(track >= 0) { "AAC пришёл до формата" }
                                    val buffer = checkNotNull(encoder.getOutputBuffer(index))
                                    buffer.position(info.offset)
                                    buffer.limit(info.offset + info.size)
                                    // Один выходной буфер AAC-LC — один кадр. Входные PTS не
                                    // определяют длительность хвоста после опустошения кодека.
                                    info.presentationTimeUs = frames * FRAME_SAMPLES * 1_000_000 / sampleRate
                                    info.flags = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv()
                                    writer.writeSampleData(track, buffer, info)
                                    frames++
                                }
                            } finally {
                                outputEnded = ended
                                encoder.releaseOutputBuffer(index, false)
                            }
                            lastProgress = SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
            check(track >= 0 && frames * FRAME_SAMPLES >= samples + priming) { "Неполный выход AAC" }
            // Явная длительность последнего кадра: не полагаемся на эвристику muxer.
            info.set(0, 0, frames * FRAME_SAMPLES * 1_000_000 / sampleRate, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            writer.writeSampleData(track, ByteBuffer.allocate(0), info)
            writer.stop()
            writer.release()
            muxer = null
            encoder.stop()
            encoder.release()
            codec = null
            // MediaMuxer не записывает encoder-delay/padding. Стандартный edit list
            // сохраняет все кадры для декодера, но предъявляет только исходные отсчёты.
            M4aGapless.trim(output, samples, sampleRate, priming)
            complete = true
        } finally {
            runCatching { codec?.release() }
            runCatching { muxer?.release() }
            if (!complete) output.delete()
        }
    }
}
