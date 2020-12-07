use anyhow::{Context, Error};
use flate2::write::GzEncoder;
use rayon::prelude::*;
use std::{io::Write, path::Path};
use xz2::write::XzEncoder;

pub(crate) enum CompressionFormat {
    Gz,
    Xz,
}

impl CompressionFormat {
    pub(crate) fn encode(&self, path: impl AsRef<Path>) -> Result<Box<dyn Encoder>, Error> {
        let extension = match self {
            CompressionFormat::Gz => ".gz",
            CompressionFormat::Xz => ".xz",
        };
        let mut os = path.as_ref().as_os_str().to_os_string();
        os.push(extension);
        let path = Path::new(&os);

        if path.exists() {
            crate::util::remove_file(path)?;
        }
        let file = crate::util::create_new_file(path)?;

        Ok(match self {
            CompressionFormat::Gz => Box::new(GzEncoder::new(file, flate2::Compression::best())),
            CompressionFormat::Xz => {
                // Note that preset 6 takes about 173MB of memory per thread, so we limit the number of
                // threads to not blow out 32-bit hosts.  (We could be more precise with
                // `MtStreamBuilder::memusage()` if desired.)
                let stream = xz2::stream::MtStreamBuilder::new()
                    .threads(Ord::min(num_cpus::get(), 8) as u32)
                    .preset(6)
                    .encoder()?;
                Box::new(XzEncoder::new_stream(file, stream))
            }
        })
    }
}

pub(crate) trait Encoder: Send + Write {
    fn finish(self: Box<Self>) -> Result<(), Error>;
}

impl<W: Send + Write> Encoder for GzEncoder<W> {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        GzEncoder::finish(*self).context("failed to finish .gz file")?;
        Ok(())
    }
}

impl<W: Send + Write> Encoder for XzEncoder<W> {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        XzEncoder::finish(*self).context("failed to finish .xz file")?;
        Ok(())
    }
}

pub(crate) struct CombinedEncoder {
    encoders: Vec<Box<dyn Encoder>>,
}

impl CombinedEncoder {
    pub(crate) fn new(encoders: Vec<Box<dyn Encoder>>) -> Box<dyn Encoder> {
        Box::new(Self { encoders })
    }
}

impl Write for CombinedEncoder {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.write_all(buf)?;
        Ok(buf.len())
    }

    fn write_all(&mut self, buf: &[u8]) -> std::io::Result<()> {
        self.encoders
            .par_iter_mut()
            .map(|w| w.write_all(buf))
            .collect::<std::io::Result<Vec<()>>>()?;
        Ok(())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.encoders
            .par_iter_mut()
            .map(|w| w.flush())
            .collect::<std::io::Result<Vec<()>>>()?;
        Ok(())
    }
}

impl Encoder for CombinedEncoder {
    fn finish(self: Box<Self>) -> Result<(), Error> {
        self.encoders
            .into_par_iter()
            .map(|e| e.finish())
            .collect::<Result<Vec<()>, Error>>()?;
        Ok(())
    }
}
