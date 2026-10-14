package hev.htproxy

object TProxyService {
    init {
        try {
            System.loadLibrary("hev-socks5-tunnel")
        } catch (e: UnsatisfiedLinkError) {
            e.printStackTrace()
        }
    }

    @JvmStatic
    external fun TProxyStartService(configPath: String, fd: Int): Boolean

    @JvmStatic
    external fun TProxyStopService(): Boolean

    @JvmStatic
    external fun TProxyIsRunning(): Boolean

    @JvmStatic
    external fun TProxyGetStats(): LongArray?
}
