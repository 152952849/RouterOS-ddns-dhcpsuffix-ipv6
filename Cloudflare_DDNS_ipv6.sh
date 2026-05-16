# RouterOS IPv6-DHCP Client脚本
# Cloudflare DDNS + 防火墙地址列表 + PushPlus 通知 - 多设备前缀+固定后缀模式-数组（仅在IP变化时推送）
# 采用前缀+固定后缀模式避免邻居发现ip更新不及时 部分设备随机mac(如win)要更改固定

# ---------- 配置区域（请按需修改）----------
:local cfToken "" # cloudflare 帐户 API 令牌 DNS Write权限
:local cfZoneID "" # cloudflare 域名区域ID
:local pushplusToken "" # pushplus 消息Token
:local domainList {"a.com";"b.com"} # 多域名采用数组形式
:local suffixList {"1111:2222:3333:4444";"5555:6666:7777:8888"} # 设备后缀
:local recordIDList {"";""} # 对应域名 recordID
:local listNameList {"A_accept_list";"B_accept_list"} # RouterOS IPv6 放行 firewall List列表
# ---------- 配置结束 ----------

:if ($"pd-valid" = "1") do={
    :local newPrefix $"pd-prefix"

    # 提取纯前缀（去掉子网掩码）
    :local cidrNetwork $newPrefix
    :local pos [:find $newPrefix "/"]
    :if ($pos >= 0) do={ :set cidrNetwork [:pick $newPrefix 0 $pos] }

    # 修复：将前缀末尾的 "::" 替换为单个 ":"，确保拼接出合法 IPv6
    :local dcolonPos [:find $cidrNetwork "::"]
    :if ($dcolonPos >= 0) do={
        :set cidrNetwork ([:pick $cidrNetwork 0 $dcolonPos] . ":")
    }
    :if ([:pick $cidrNetwork ([:len $cidrNetwork] - 1)] != ":") do={
        :set cidrNetwork ($cidrNetwork . ":")
    }

    :log info "IPv6 Prefix 已更新: $cidrNetwork"

    :for i from=0 to=([:len $domainList] - 1) do={
        :local fullDomain ($domainList->$i)
        :local suffix   ($suffixList->$i)
        :local recordID ($recordIDList->$i)
        :local listName ($listNameList->$i)

        :local ipv6Report ($cidrNetwork . $suffix)
        :log info ("[$fullDomain] 拼接得到的 IPv6: " . $ipv6Report)

        # 1. 获取 Cloudflare 当前记录
        :local getUrl ("https://api.cloudflare.com/client/v4/zones/" . $cfZoneID . "/dns_records/" . $recordID)
        :local getResult [/tool fetch http-method=get mode=https url=$getUrl check-certificate=no output=user as-value http-header-field="Authorization: Bearer $cfToken"]
        :local getData ($getResult->"data")

        :local currentContent ""
        :local startPos [:find $getData "\"content\":\""]
        :if ($startPos >= 0) do={
            :local contentStart ($startPos + 11)
            :local endPos [:find $getData "\"" $contentStart]
            :if ($endPos >= 0) do={ :set currentContent [:pick $getData $contentStart $endPos] }
        }

        # 2. 比较并决定是否更新
        :if ($ipv6Report != $currentContent) do={
            # Cloudflare 更新
            :local putUrl ("https://api.cloudflare.com/client/v4/zones/" . $cfZoneID . "/dns_records/" . $recordID)
            :local putData ("{\"type\":\"AAAA\",\"name\":\"" . $fullDomain . "\",\"content\":\"" . $ipv6Report . "\",\"ttl\":120,\"proxied\":false}")
            :local headers {"Authorization: Bearer $cfToken"; "Content-Type: application/json"}
            /tool fetch http-method=put mode=https url=$putUrl check-certificate=no output=user as-value http-header-field=$headers http-data=$putData
            :log info ("[$fullDomain] Cloudflare 已更新 -> $ipv6Report")

            # 防火墙地址列表（先删后加）
            :local fwEntry [/ipv6 firewall address-list find list=$listName comment=("CFDDNS:" . $fullDomain)]
            :if ([:len $fwEntry] > 0) do={ /ipv6 firewall address-list remove $fwEntry }
            /ipv6 firewall address-list add list=$listName address=$ipv6Report comment=("CFDDNS:" . $fullDomain)
            :log info ("[$fullDomain] 防火墙列表 [$listName] 已更新 -> $ipv6Report")

            # ---------- PushPlus 通知（手动编码空格和冒号）----------
            :local pushTitle "$fullDomain DDNS Updated"
            :local pushContent "New IPv6: $ipv6Report"

            # 编码 pushTitle
            :local pushTitleEncoded ""
            :for j from=0 to=([:len $pushTitle] - 1) do={
                :local c [:pick $pushTitle $j]
                :if ($c = " ") do={
                    :set pushTitleEncoded ($pushTitleEncoded . "%20")
                } else={
                    :if ($c = ":") do={
                        :set pushTitleEncoded ($pushTitleEncoded . "%3A")
                    } else={
                        :set pushTitleEncoded ($pushTitleEncoded . $c)
                    }
                }
            }

            # 编码 pushContent
            :local pushContentEncoded ""
            :for j from=0 to=([:len $pushContent] - 1) do={
                :local c [:pick $pushContent $j]
                :if ($c = " ") do={
                    :set pushContentEncoded ($pushContentEncoded . "%20")
                } else={
                    :if ($c = ":") do={
                        :set pushContentEncoded ($pushContentEncoded . "%3A")
                    } else={
                        :set pushContentEncoded ($pushContentEncoded . $c)
                    }
                }
            }

            :local postData ("token=" . $pushplusToken . "&title=" . $pushTitleEncoded . "&content=" . $pushContentEncoded)
            :local pushResult [/tool fetch http-method=post mode=https url="https://www.pushplus.plus/send" check-certificate=no output=user as-value http-header-field="Content-Type: application/x-www-form-urlencoded" http-data=$postData]
            :log info ("[$fullDomain] PushPlus 返回: " . $pushResult)
        } else={
            :log info ("[$fullDomain] Cloudflare 无需更新 (当前IP: $currentContent)")
            # 防火墙条目刷新
            :local fwEntry [/ipv6 firewall address-list find list=$listName comment=("CFDDNS:" . $fullDomain)]
            :if ([:len $fwEntry] > 0) do={ /ipv6 firewall address-list remove $fwEntry }
            /ipv6 firewall address-list add list=$listName address=$ipv6Report comment=("CFDDNS:" . $fullDomain)
            :log info ("[$fullDomain] 防火墙列表 [$listName] 条目已刷新")
        }
    }
}
