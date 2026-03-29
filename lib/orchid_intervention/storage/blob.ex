defmodule OrchidIntervention.Storage.Blob do
  # 这个和 OrchidStratum 的 BlobStorage 基本一样，但是在
  # 应用上要有所区别（主要一旦放进一个应用里边，会导致 OrchidStratum
  # 的垃圾回收机制很复杂）

  # @behaviour Orchid.Repo
  # @behaviour Orchod.Repo.ContentAddressable
  # @behaviour Orchod.Repo.GC
end
