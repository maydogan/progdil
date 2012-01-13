#~ pathname, pythonconfig, yaml kullan
require 'pathname'
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {}) #~ Yapılandırmada presentation' a ait bölümleri al

# Sunum dizini
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')  #~  
# Öntanımlı landslide yapılandırması
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')  #~ 1.si varsa 1.sini al eğer yoksa 2.cisini al
# Sunum indeksi
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')  #~ "/" ile birleştir
# İzin verilen en büyük resim boyutları
IMAGE_GEOMETRY = [ 733, 550 ]  #~ Resmin boyutları 733, 550 olsun
# Bağımlılıklar için yapılandırmada hangi anahtarlara bakılacak
DEPEND_KEYS    = %w(source css js)  #~ list ["source", "css", "js"].. source, css, js' yi listele
# Vara daima bağımlılık verilecek dosya/dizinler
DEPEND_ALWAYS  = %w(media) #~ 
# Hedef Görevler ve tanımları
TASKS = { #~ HASH oluştur, içerisie aşağıdaki çiftleri yerleştir
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}

# Sunum bilgileri
presentation   = {}
# Etiket bilgileri
tag            = {}

class File
  @@absolute_path_here = Pathname.new(Pathname.pwd)
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path)
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

def png_comment(file, string)
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end

def png_optim(file, threshold=40000)
  #~ Belli bir eşik değerine(40000) göre resmi optime et
  return if File.new(file).size < threshold # Dosyanın boyutu threshold' dan küçükse geri dön
  sh "pngnq -f -e .png-nq #{file}" # değilse ???
  out = "#{file}-nq"
  if File.exist?(out) 
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  #~ Resmin işlendiğini belirtmek için not düş
  png_comment(file, 'raked')
end

def jpg_optim(file) #~
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end

def optim #~
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  # Optimize edilmişleri çıkar
  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  # Boyut düzeltmesi yap
  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end

  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  # Optimize edilmiş resimlerin kullanıldığı slaytları, bu resimler slayta
  # gömülü olabileceğinden tekrar üretelim.  Nasıl?  Aşağıdaki berbat
  # numarayla.  Resim'e ilişik bir referans varsa dosyaya dokun.
  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end

# Alt dizinlerde yapılandırma dosyasına mutlak dosya yoluyla erişiyoruz
default_conffile = File.expand_path(DEFAULT_CONFFILE)  #~ DEFAULT_CONFFILE dosyasının tam yolunu al

# Sunum bilgilerini üret
FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir| #~ Dir['*'] '_' ile başlamayan tüm dizinleri getir
  next unless File.directory?(dir) #~ Eğer dizin yoksa pas geç, devam et
  chdir dir do #~ Dizinin içerisine gir
    name = File.basename(dir) #~ Dizinin basename(alt kısmını) al yani /home/may/foo => foo alır
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    #~ presentation.cfg dosyası varsa onu, yoksa default_conffile dosyasını al
    config = File.open(conffile, "r") do |f| #~ '='e göre parçalıyıp hash dönen bir ifade
      PythonConfig::ConfigParser.new(f)
    end

    landslide = config['landslide'] #~
    if ! landslide #~ landslide yoksa hata ver
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end

    if landslide['destination'] #~ presentation.cfg dosyasının içinde key'i, destination olan varsa hata ver ve çık
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end

    if File.exists?('index.md') #~ index.md dosyası yoksa
      base = 'index' #~ base index olsun
      ispublic = true #~ Genel bir tek şablon sunum/slayt vardır
    elsif File.exists?('presentation.md') # presentation.mf yok ise
      base = 'presentation' #~ base presentation olsun
      ispublic = false #~ Çoklu bir şablon sunum/slayt vardır
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı" #~ Diğer durumda  "sunum kaynağı presentation.md veya index.md olmalı" 
      #~şeklinde hata versin 
            exit 1
    end
    #~ Sunumun html sayfası  ve resmi için ayarlar
    basename = base + '.html' #~ basename = basedeğişkeni.html şeklinde olsun
    thumbnail = File.to_herepath(base + '.png') #~ Resmin tam yolunu tanımla
    target = File.to_herepath(basename) #~ html sayfanın(sunum) tam yolunu tanımla

    # bağımlılık verilecek tüm dosyaları listele
    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v| #~ css dizinini ve altındaki dizin(dosya)ları da al
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
      #~ css/a.css css/b.css ise => css + b.css + css işlemini gerçeklerştir
    end
    #~ deps = ["css", "a.css", "b.css"]
    # bağımlılık ağacının çalışması için tüm yolları bu dizine göreceli yap
    deps.map! { |e| File.to_herepath(e) } # bu dizindeki pathlerini al
    deps.delete(target) #~ html sayfasını 'deps' ten sil
    deps.delete(thumbnail) #~ png dosyasını 'deps' ten sil

    # TODO etiketleri işle
    tags = []

   presentation[dir] = { #~ global presentation
      :basename  => basename,	#~ üretilecek sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları                           #~ css vs..
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli) #~ html
      :thumbnail => thumbnail, 	# sunum için küçük resim                          #~ png
    }
  end
end

# Boş taglara atama yap
presentation.each do |k, v|   # Yukarda tanımlanan hash'de dolaş. 
  v[:tags].each do |t|  
    tag[t] ||= []             # Eğer ki tags etiketi boş ise
    tag[t] << k               # k verisini ekle
  end
end

# Görev tablosunu hazırla
tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]

# Görevleri dinamik olarak üret
presentation.each do |presentation, data|
  # her alt sunum dizini için bir alt görev tanımlıyoruz
  ns = namespace presentation do
    # sunum dosyaları
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}" #~ Konsoldan lanslide ile conffile
        # XXX: Slayt bağlamı iOS tarayıcılarında sorun çıkarıyor.  Kirli bir çözüm!
        #~ presentation.html'de
        # ([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\) geçenleri
        # \1true\2 yap
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'


        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]  #~ data[:basename], yani en alt dosya presentation.html değilse
                                                   #~ presentation.html'in ismini data[:basename] olarak değiştir
        end
      end
    end

    # küçük resimler
    file data[:thumbnail] => data[:target] do #~ png resim ile ilgili bir göreve bakıyor
      next unless data[:public] #~ data[:public] yoksa devam et
      sh "cutycapt " +          #~ ile konsoldan kod çalıştır
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}" #~ Genişlik ve yüksekliğini 240 olarak ayarla
      png_optim(data[:thumbnail])
    end

    task :optim do #~ $ rake optim : ifadesi presentation dizinine girip resimleri optim fonksiyonu ile optime eder
      chdir presentation do
        optim
      end
    end

    task :index => data[:thumbnail] #~ $ rake index : ifadesi sunumun png'sine bağımlı olarak data[:thumbnail] görevini çalıştırır
                                    #~ Sayfa için önce resim gerek

    task :build => [:optim, data[:target], :index]
                                   #~ $ rake build : deyince optim,
                                   #~ data[:target](html), index çalışması gerektir bağımlıdır
                                   #~ Yani resimleri optime et
                                   #~ Çalıştır; Anasayfa ile ilgili görevleri çalıştır

    task :view do  #~  $ rake view
      if File.exists?(data[:target]) #~ Görevler dizini yoksa onu oluştur
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end

    task :run => [:build, :view] #~ $ rake run
                                 # Görev build, view çalışmalı

    task :clean do #~ $ rake clean
      rm_f data[:target]       #~ data[:target] dizini sil / html'i siliyoruz
      rm_f data[:thumbnail]    #~ data[:thumbnail] dizini sil / png'yi siliyoruz
    end

    task :default => :build #~ $rake default:
                            # build görevine bağlıdır.
  end

  # alt görevleri görev tablosuna işle
  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end

namespace :p do
  # görev tablosundan yararlanarak üst isim uzayında ilgili görevleri tanımla
  tasktab.each do |name, info|
    desc info[:desc] #~ desc fonksiyonu yardımıyla kullanıcıya bilgi göster
    task name => info[:tasks]
    task name[0] => name
  end

  task :build do #~ GENEL olarak INDEX_FILE ismindeki dosyaya JEYKLL ismini oluştur
                # ör:
                # index
                # ---

    index = YAML.load_file(INDEX_FILE) || {} #~ INDEX_FILE varsa al, yoksa "{}"'i al
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
  task :menu do #~ Sunum menüsü oluşturup sunumu seç, sunumu göster (RUN et)
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
    name = choose do |menu|
      menu.default = "1" #~ Defoult olarak sunumlardan 1. sunumu ilk sunumu seçmemizi iste
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]
    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu #~ "$rake menu" yerine "rake m" ifadesi de kullanılabilir
end

desc "sunum menüsü"
task :p => ["p:menu"] #~ "$rake p" deyince "$rake p:menu" çalışır, menü gelir ve böylece sunumu açabiliriz
task :presentation => :p


# rake build mesala derleme yapıyor sanırsam.
# rake p : Sunumları göster
