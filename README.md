# RouterOS IPv6-DHCP Client脚本
## RouterOS脚本- Cloudflare DDNS + 防火墙地址列表 + PushPlus 通知 - 多设备前缀+固定后缀模式（仅在IP变化时推送）
### 采用前缀+固定后缀模式避免邻居发现ip更新不及时 部分设备随机mac(如win)要更改固定

#### cloudflare获取Record ID
```
curl --request GET \
  --url "https://api.cloudflare.com/client/v4/zones/{zonesid}/dns_records?type=AAAA&name={域名}" \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer {对应域名ddnstoken}"
  ```
### 使用方式
脚本复制到 RouterOS -ipv6 -dhcp client -Advanced -script
