package cz.tomaspetrik.petrikvpn

import java.net.Inet4Address
import java.net.InetAddress

/**
 * Replaces `0.0.0.0/0` with complementary IPv4 prefixes that omit [excludeCidrs],
 * so WSS to the VPS stays off the TUN without needing VpnService.protect(fd).
 */
object Ipv4RouteCarver {
    fun applyExclusions(allowedCidrs: List<String>, excludeCidrs: List<String>): List<String> {
        if (excludeCidrs.isEmpty()) {
            return allowedCidrs
        }
        val excludes = excludeCidrs.mapNotNull { parseCidr(it) }
        if (excludes.isEmpty()) {
            return allowedCidrs
        }
        val out = ArrayList<String>()
        for (allowed in allowedCidrs) {
            val net = parseCidr(allowed) ?: continue
            if (net.prefix == 0 && net.address == 0) {
                var parts: List<Cidr> = listOf(net)
                for (ex in excludes) {
                    parts = parts.flatMap { carve(it, ex) }
                }
                out.addAll(parts.map { it.toCidrString() })
            } else {
                out.add(allowed)
            }
        }
        return out
    }

    private data class Cidr(val address: Int, val prefix: Int) {
        fun toCidrString(): String {
            val b0 = (address ushr 24) and 0xff
            val b1 = (address ushr 16) and 0xff
            val b2 = (address ushr 8) and 0xff
            val b3 = address and 0xff
            return "$b0.$b1.$b2.$b3/$prefix"
        }

        fun networkMask(): Int {
            if (prefix == 0) return 0
            return (-1) shl (32 - prefix)
        }

        fun contains(other: Cidr): Boolean {
            if (other.prefix < prefix) return false
            val mask = networkMask()
            return (address and mask) == (other.address and mask)
        }
    }

    private fun parseCidr(raw: String): Cidr? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val parts = trimmed.split("/", limit = 2)
        val host = parts[0]
        val prefix = if (parts.size > 1) parts[1].toIntOrNull() ?: 32 else 32
        val addr = InetAddress.getByName(host) as? Inet4Address ?: return null
        val bytes = addr.address
        val ip = ((bytes[0].toInt() and 0xff) shl 24) or
            ((bytes[1].toInt() and 0xff) shl 16) or
            ((bytes[2].toInt() and 0xff) shl 8) or
            (bytes[3].toInt() and 0xff)
        val p = prefix.coerceIn(0, 32)
        val mask = if (p == 0) 0 else (-1) shl (32 - p)
        return Cidr(ip and mask, p)
    }

    /** Split [parent] into CIDRs that cover parent minus [exclude] (exclude must be inside parent). */
    private fun carve(parent: Cidr, exclude: Cidr): List<Cidr> {
        if (!parent.contains(exclude)) {
            return listOf(parent)
        }
        if (parent.address == exclude.address && parent.prefix == exclude.prefix) {
            return emptyList()
        }
        val result = ArrayList<Cidr>()
        var current = parent
        while (current.prefix < exclude.prefix) {
            val nextPrefix = current.prefix + 1
            val bit = 1 shl (32 - nextPrefix)
            val left = Cidr(current.address, nextPrefix)
            val right = Cidr(current.address or bit, nextPrefix)
            if (left.contains(exclude)) {
                result.add(right)
                current = left
            } else {
                result.add(left)
                current = right
            }
        }
        return result
    }
}
