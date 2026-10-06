<script lang="ts">
let { size = 36 }: { size?: number } = $props();
</script>

<img
  class="block shrink-0"
  src={`${import.meta.env.BASE_URL}images/icon.png`}
  width={size}
  height={size}
  alt=""
>
