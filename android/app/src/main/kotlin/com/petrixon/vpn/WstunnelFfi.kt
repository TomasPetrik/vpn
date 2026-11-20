package com.petrixon.vpn

/**
 * JNI façade for [libwstunnel_ffi.so] built from native/wstunnel_ffi.
 */
object WstunnelFfi {
    init {
        System.loadLibrary("wstunnel_ffi")
    }

    /**
     * Starts the client. Returns null on success, otherwise an error message.
     */
    @JvmStatic
    external fun nativeStart(configJson: String): String?

    @JvmStatic
    external fun nativeStop()

    @JvmStatic
    external fun nativeIsRunning(): Int

    fun start(configJson: String) {
        val err = nativeStart(configJson)
        if (err != null) {
            throw IllegalStateException(err)
        }
    }

    fun stop() {
        nativeStop()
    }

    fun isRunning(): Boolean = nativeIsRunning() != 0
}
