# pathname, pythonconfig, yaml gereklidir
require 'pathname'
require 'pythonconfig'
require 'yaml'

# Yapılandırmada presentation(sunum)'a karşılık gelen bilgileri al eğer yoksa, {}-> boş sözlük al
CONFIG = Config.fetch('presentation', {})

# directory bilgilerini al eğer yoksa p'yi al
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
# 'conffile''a karşılık gelen bilgileri al, yoksa '_templates/presentation.cfg' al
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
# "p/index.html" veya "directory/index.html" yap
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')
# İzin verilen en büyük resim boyutları 733, 550 olsun
IMAGE_GEOMETRY = [ 733, 550 ]
# ["source", "css", "js"] şeklinde yazılsın. Yani source, css, js' yi listesi.
DEPEND_KEYS    = %w(source css js)
DEPEND_ALWAYS  = %w(media) # liste = ['media']

# HASH oluştur ve içerisine yapılacak görevleri yerleştir
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

# Sunum bilgilerini içeren sözlük
presentation   = {}
# Tag bilgilerini içeren sözlük
tag            = {}

class File
  # .pdf'den aldığı yolu absolute_path_here değişkenine ata
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  # Verilen path' e göre yeni path oluştur
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end

  # Bu path'de directory var mı? diye bak
  # o path'deki tüm dosya/dizinlerden dosya olanları al ve [path] diyerek dön
  def self.to_filelist(path)
    File.directory?(path)
      FileList[File.join(path, '*')].select { |f| File.file?(f) }
      [path]
  end
end

# Küçük boyutlu resim(png) commentle
def png_comment(file, string)
  # chunky_png kütüphanesi ile png dosyalarını oku ve yaz
  require 'chunky_png'
  # oily_png ile chunky_png kütüphanesinin çalışması hızlandı
  require 'oily_png'

  # ChunkyPNG ile resimleri al
  image = ChunkyPNG::Image.from_file(file)
  # Hedef veriye ulaşarak 'raked' olarak güncelle
  image.metadata['Comment'] = 'raked'
  image.save(file)  # ve kaydet
end

# png uzantılı resimleri optimize et
def png_optim(file, threshold=40000)
  # Belli bir eşik değerine(40000) göre resmi optimize et
  # Resmin boyutu threshold' dan küçükse geri dön
  return if File.new(file).size < threshold
  # resmin boyutunu küçültürek optimize et
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  # Resmin işlendiğini not düş
  png_comment(file, 'raked')
end

# jpg uzantılı resimleri optimize et
def jpg_optim(file)
  # jpegoptim ile resmi istenilen şekilde optimize et
  sh "jpegoptim -q -m80 #{file}"
  # mogrify ile optimize edilen file'ı bildir
  sh "mogrify -comment 'raked' #{file}"
end

# Public olarak bütün png, jpg ve jpeg uzantılı resimleri optimize et
def optim

  # Bütün png, jpg ve jpeg dosyalarını pngs ve jpgs olarak listele
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  # optimize edilmemiş resimleri
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

   # Boyutlarını düzenle
  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    # Her bir resmin yüksekliğini ve genişliğini w, h değişkenlerine ata
    size, i = [w, h].each_with_index.max
    # Yükseklik ve genişliklerinin boyutlarını size' e ata
    # Eğer size IMAGE_GEOMETRY' den büyükse istenilen şekilde boyutlandırarak optimize et
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}" # Yeniden boyutlandırılan resmi bildir
    end
  end

  # Tüm optimize edilmesi gereken resimleri optimize etti
  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  # pngs ve jpgs'den gelen resimleri al bunlardan */* path'indeki tüm markdown
  # uzantılı dosyalarının içinde bu resimler var ise sessiz bir şekilde(grep -q)
  # o dosyayı oluştur
  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

# DEFAULT_CONFFILE  için 'conffile''a karşılık gelen bilgileri al,
# yoksa '_templates/presentation.cfg' almıştık.
# Bu path'in tam yolunu al
default_conffile = File.expand_path(DEFAULT_CONFFILE)

# "_" ile başlamayan tüm doslayaları al ve bunlarda gez
FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  # Eğer ki bu dosya bir dizin değilse pas geç, devam et
  next unless File.directory?(dir)
  # Dizinin içerisine gir
  chdir dir do
    # Dizinin basename(alt kısmını) al yani /home/may/foo => foo alır
    name = File.basename(dir)
    # presentation.cfg dosyası varsa onu, yoksa default_conffile dosyasını conffile'e ata
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f| # Dosyayı aç
      # PythonConfig:ConfigParser modülü ile yeni bir config dosyasını ayrıştır al.
      PythonConfig::ConfigParser.new(f)
    end

    # config de aldığımız bilgilerden key'i 'landslide' olanı al
    landslide = config['landslide']

    if ! landslide  # landslide yoksa hata ver ve çık
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end

    if landslide['destination'] # landslide varsa ve 'destination' ayarı kullanılmış ise hata ver ve çık
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end
    # index.md dosyası var mı? Varsa base'e "*.md" uzantılı dosyanın adını ata
    if File.exists?('index.md')
      base = 'index'
      # Genel bir tek şablon sunum/slayt vardır
      ispublic = true

    # presentation.md dosyası var mı? Varsa base'e presentation'u ata
    elsif File.exists?('presentation.md')
      base = 'presentation'
      # Çoklu bir şablon sunum/slayt vardır
      ispublic = false

    # Her iki *.md dosyaları yoksa gerekli hatayı ver ve çık
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end

    # Sunumun html sayfası  ve resmi için ayarlar
    # base ile html sayfası oluşturup basename' e ata
    basename = base + '.html'
    # Resmin tam yolunu thumbnail değişkenine ata
    thumbnail = File.to_herepath(base + '.png') )
    # html sayfasının(sunum) tam yolunu target değişkenine ata
    target = File.to_herepath(basename)


    # bağımlılık verilecek tüm dosyaları listele
    deps = []
    # css, source, js dizinini ve altındaki dizin(dosya)ları da al
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
      # css/a.css css/b.css ise => css + b.css + css işlemini gerçekleştir gibi.
    end
    # deps = ["css", "a.css", "b.css"] gibi

    # bu dizindeki dosyların pathlerini al, html sayfasını ve png dosyasını 'deps' ten sil
    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)

    tags = []  # tags dizisi oluştur

   # Sunum dizini ile ilgili bilgileri persentation' da tanımla
   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)    # html yani
      :thumbnail => thumbnail, 	# sunum için küçük resim			     # png yani
    }
  end
end

# Boş taglara atama yap
# Yukarda tanımlanan presentation hash'inde dolaş
presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []              # Eğer ki tag boş ise
    tag[t] << k                # Boş tagı doldur
  end
end

# Hash oluştur ve içerisine görevleri ve açıklamalarını ata
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

presentation.each do |presentation, data|   # Sunumlarda dolaş ve
  ns = namespace presentation do            # Yeni bir isim uzayı oluştur ve ns' ye ata
    # html dosyasının bağımlılıklarını al
    file data[:target] => data[:deps] do |t|
      # sunumun olduğu dizine gir
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
        # data[:basename], yani en alt dosya presentation.html değilse
        unless data[:basename] == 'presentation.html'
          # presentation.html'i data[:basename] taşı
          mv 'presentation.html', data[:basename]
        end
      end
    end

    # png resim ile ilgili bir göreve bakıyor
    file data[:thumbnail] => data[:target] do
      next unless data[:public]			  # data[:public] yoksa devam et
      sh "cutycapt " +				  # cutycapt ile konsoldan ekran görüntüsü al
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " + # Verilen adresteki resmi al
          "--out=#{data[:thumbnail]} " + # Hedef dosyaya aktar
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " + # minimum genişlik 1024 olsun
          "--min-height=768 " + # minumum yükseklik 768 olsun
          "--delay=1000" # sunumlar arası 1000(ms) geçiş olsun
      # Optimize edilen dosya mogrify ile kaydedildi
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      # Optimize edilen dosyayı data[:thumbnail]' e kaydet
      png_optim(data[:thumbnail])
    end

    task :optim do # $ rake optim : ifadesi presentation dizinine girip resimleri optim fonksiyonu ile optime eder
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail]   # $ rake index : ifadesi sunumun png'sine bağımlı olarak data[:thumbnail] görevini çalıştırır
				      # Sayfa için önce resim gerekli

    task :build => [:optim, data[:target], :index]
                                # $ rake build : deyince optim,
                                # optim, data[:target](html dosyası), index çalışması gerektir bağımlıdır
                                # Yani resimleri optime et(:optim)
                                # Çalıştır; Anasayfa ile ilgili görevleri çalıştır


    #  $ rake view: görüntüleme görevini çalıştır
    task :view do
      # Görev dosyası var mı? Varsa data[:target] var olduğu için data[:directory] dizinine dokun
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"

      # Görev dosyası yoksa gerekli hatayı ver ve çık
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view]  # $ rake run
				   # Görev build, view çalışmalı
    task :clean do
      rm_f data[:target]          # data[:target] 'i sil / html'i siliyoruz
      rm_f data[:thumbnail]       # data[:thumbnail] 'i sil / png'yi siliyoruz
    end

    task :default => :build    # $rake default:
			       # build görevine bağlıdır.
  end

  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]             # desc fonksiyonu yardımıyla kullanıcıya bilgi göster
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do   # GENEL olarak INDEX_FILE ismindeki dosyaya JEYKLL ismini oluştur
		   # ör:
                   # index
                   # ---

    index = YAML.load_file(INDEX_FILE) || {} #~ INDEX_FILE varsa al, yoksa "{}" ->> boş sözlük  al
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end
  desc "sunum menüsü"
  task :menu do  # Sunum menüsü oluşturup sunumu seç, sunumu göster (RUN et)
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1"    # Default olarak sunumlardan 1. sunumu ilk sunum olarak ayarla
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu  # "$rake menu" yerine "rake m" ifadesi de kullanılabilir
end

desc "sunum menüsü"
task :p => ["p:menu"]  # "$rake p" deyince "$rake p:menu" çalışır, menü gelir ve böylece sunumu açabiliriz
task :presentation => :p
